import Foundation

/// A fake ELM327 and car, used by the tests and the app's demo mode. It answers
/// in the ELM text format, including multi-frame output and negative responses.
public actor SimulatedCar: ELMLink {
    struct FakeECU {
        let rx: String
        let usesUDS: Bool
        var entries: [[UInt8]]
        /// Faults that return right after a clear: the part is still broken.
        var permanent: [[UInt8]]
    }

    private var ecus: [String: FakeECU] = [
        "7E0": FakeECU(rx: "7E8", usesUDS: true,
                       entries: [[0x04, 0x01, 0x92, 0x08], [0x24, 0x63, 0x00, 0x08], [0x01, 0x00, 0x13, 0x08]],
                       permanent: []),
        "740": FakeECU(rx: "760", usesUDS: false, entries: [[0xC0, 0x35, 0x48]], permanent: []),
        "752": FakeECU(rx: "772", usesUDS: true, entries: [[0x90, 0x01, 0x13, 0x09]], permanent: [[0x90, 0x01, 0x13, 0x09]]),
        "745": FakeECU(rx: "765", usesUDS: false, entries: [[0xD1, 0x40, 0x48]], permanent: []),
        "743": FakeECU(rx: "763", usesUDS: true, entries: [], permanent: []),
        "742": FakeECU(rx: "762", usesUDS: true, entries: [], permanent: []),
    ]

    private var header = "7DF"
    private var filter: String?
    public var running: Bool
    public var moving: Bool
    private let latency: UInt64
    private let start = Date()

    public init(latencyMs: UInt64 = 0, running: Bool = false, moving: Bool = false) {
        self.latency = latencyMs * 1_000_000
        self.running = running
        self.moving = moving
    }

    public func setRunning(_ running: Bool, moving: Bool = false) {
        self.running = running
        self.moving = moving
    }

    public func command(_ text: String, timeout: TimeInterval) async throws -> String {
        if latency > 0 { try await Task.sleep(nanoseconds: latency) }
        let cmd = text.uppercased().replacingOccurrences(of: " ", with: "")
        if cmd.hasPrefix("AT") { return at(String(cmd.dropFirst(2))) + "\r\r>" }
        guard let bytes = ELMParser.hexBytes(cmd) else { return "?\r\r>" }
        return respond(bytes) + "\r\r>"
    }

    private func at(_ cmd: String) -> String {
        switch true {
        case cmd == "Z": header = "7DF"; filter = nil; return "ELM327 v2.2"
        case cmd == "I": return "ELM327 v2.2 (démo)"
        case cmd == "RV": return running ? "14.1V" : "12.4V"
        case cmd == "FI": return "BUS INIT: ERROR"
        case cmd == "DPN": return "A6"
        case cmd == "DP": return "AUTO, ISO 15765-4 (CAN 11/500)"
        case cmd.hasPrefix("FC"): return "OK"
        case cmd.hasPrefix("SH"): header = String(cmd.dropFirst(2)); return "OK"
        case cmd.hasPrefix("CRA"): filter = cmd.count > 3 ? String(cmd.dropFirst(3)) : nil; return "OK"
        default: return "OK"
        }
    }

    private func respond(_ request: [UInt8]) -> String {
        if header == "7DF" { return obd(request) }
        if header == "7E0", request[0] < 0x10 { return obd(request) }
        guard var ecu = ecus[header], filter == ecu.rx else { return "NO DATA" }
        let sid = request[0]

        switch sid {
        case 0x10:
            return format([0x50, request[1]])
        case 0x21, 0x22:
            let key = hexString(request)
            if key == "22F187" || key == "2180" {
                return format([sid + 0x40] + Array(request.dropFirst()) + Array("8200123456".utf8))
            }
            // Two engine values: one fixed, one that follows the engine speed.
            if header == "7E0", key == "222000" { return format([0x62, 0x20, 0x00, 0x12, 0x34]) }
            if header == "7E0", key == "222001" {
                let wave = (sin(Date().timeIntervalSince(start) * 20) + 1) * 100
                return format([0x62, 0x20, 0x01, 0x00, running ? UInt8(wave) : 0])
            }
            return format([0x7F, sid, 0x31])
        case 0x3E:
            return format([0x7E, 0x00])
        case 0x19 where ecu.usesUDS:
            return format([0x59, 0x02, 0xAF] + ecu.entries.flatMap { $0 })
        case 0x17 where !ecu.usesUDS:
            return format([0x57, UInt8(ecu.entries.count)] + ecu.entries.flatMap { $0 })
        case 0x19, 0x17, 0x18:
            return format([0x7F, sid, 0x11])
        case 0x14:
            if moving { return format([0x7F, 0x14, 0x22]) }
            let wantsLong = request.count == 4
            guard wantsLong == ecu.usesUDS else { return format([0x7F, 0x14, 0x13]) }
            ecu.entries = ecu.permanent
            ecus[header] = ecu
            return format([0x54])
        default:
            return format([0x7F, sid, 0x11])
        }
    }

    private func obd(_ request: [UInt8]) -> String {
        guard let engine = ecus["7E0"] else { return "NO DATA" }
        let codes = engine.entries.flatMap { Array($0.prefix(2)) }
        switch request[0] {
        case 0x01:
            guard request.count > 1 else { return "NO DATA" }
            return pid(request[1]).map { format([0x41, request[1]] + $0) } ?? "NO DATA"
        case 0x02:
            guard request.count > 1 else { return "NO DATA" }
            if request[1] == 0x02 { return format([0x42, 0x02, 0x00] + (codes.isEmpty ? [0, 0] : Array(codes.prefix(2)))) }
            if codes.isEmpty { return "NO DATA" }
            return pid(request[1]).map { format([0x42, request[1], 0x00] + $0) } ?? "NO DATA"
        case 0x03:
            return format([0x43, UInt8(codes.count / 2)] + codes)
        case 0x07, 0x0A:
            return format([request[0] + 0x40, 0x00])
        case 0x04:
            if running { return format([0x7F, 0x04, 0x22]) }
            var cleared = engine
            cleared.entries = cleared.permanent
            ecus["7E0"] = cleared
            return format([0x44])
        case 0x09:
            guard request.count > 1, request[1] == 0x02 else { return "NO DATA" }
            return format([0x49, 0x02, 0x01] + Array("VF1JZ0G0000000001".utf8))
        default:
            return "NO DATA"
        }
    }

    private func pid(_ id: UInt8) -> [UInt8]? {
        let t = Date().timeIntervalSince(start)
        let wave = (sin(t / 2) + 1) / 2
        let rpm = running ? 800 + wave * 1400 : 0
        let speed = moving ? 30 + wave * 40 : 0

        func word(_ value: Double) -> [UInt8] {
            let v = UInt16(max(0, value))
            return [UInt8(v >> 8), UInt8(v & 0xFF)]
        }
        func byte(_ value: Double) -> [UInt8] { [UInt8(max(0, min(255, value)))] }

        switch id {
        case 0x00: return [0x98, 0x3F, 0xB0, 0x13] // supported PIDs, plus continuation
        case 0x20: return [0x80, 0x0E, 0x00, 0x01]
        case 0x40: return [0x44, 0x00, 0x00, 0x01]
        case 0x60: return [0x60, 0x00, 0x21, 0x50]
        case 0x62: return byte(125 + (running ? 20 + wave * 70 : 0))
        case 0x63: return word(360)
        case 0x51: return [0x04]
        case 0x73: return [0x01] + word((running ? 103 + wave * 25 : 101) * 100)
        case 0x78: // sensor 1 measures, sensor 2 is stuck at 0 °C, to show the alert
            return [0x03] + word((running ? 240 + wave * 180 + 40 : 60) * 10) + word(40 * 10) + [0, 0, 0, 0]
        case 0x7A: // differential and inlet only: no outlet sensor on this car
            return [0x03] + word((running ? 1 + wave * 18 : 0) * 100) + word((running ? 103 + wave * 25 : 101) * 100) + [0, 0]
        case 0x7C: return [0x01] + word((running ? 220 + wave * 160 + 40 : 60) * 10) + [0, 0]
        case 0x01:
            let count = UInt8(ecus["7E0"]?.entries.count ?? 0)
            return [count > 0 ? (0x80 | count) : 0, 0x0F, 0xE9, count > 0 ? 0x41 : 0x00]
        case 0x04: return byte((running ? 15 + wave * 45 : 0) * 2.55)
        case 0x05: return byte(88 + 40 + wave * 4)
        case 0x06: return byte(128 + wave * 8)
        case 0x07: return byte(131)
        case 0x0B: return byte(running ? 100 + wave * 70 : 101)
        case 0x0C: return word(rpm * 4)
        case 0x0D: return byte(speed)
        case 0x0F: return byte(25 + 40 + wave * 6)
        case 0x10: return word((running ? 9 + wave * 50 : 0) * 100)
        case 0x11: return byte((running ? 12 + wave * 30 : 0) * 2.55)
        case 0x1F: return word(t)
        case 0x21: return word(142)
        case 0x23: return word((running ? 300 + wave * 900 : 0) * 10)
        case 0x2C: return byte((running ? 20 + wave * 15 : 0) * 2.55)
        case 0x2D: return byte(128 + wave * 20)
        case 0x2F: return byte(62 * 2.55)
        case 0x31: return word(1830)
        case 0x33: return byte(101)
        case 0x42: return word((running ? 14.1 : 12.4) * 1000)
        case 0x46: return byte(9 + 40)
        default: return nil
        }
    }

    /// Output as ATH0 prints it: a single line, or length plus numbered segments.
    private func format(_ bytes: [UInt8]) -> String {
        if bytes.count <= 7 { return hexString(bytes) }
        var lines = [String(format: "%03X", bytes.count), "0:" + hexString(Array(bytes.prefix(6)))]
        var index = 6
        var segment = 1
        while index < bytes.count {
            let end = min(index + 7, bytes.count)
            lines.append(String(format: "%X:", segment % 16) + hexString(Array(bytes[index..<end])))
            index = end
            segment += 1
        }
        return lines.joined(separator: "\r")
    }
}
