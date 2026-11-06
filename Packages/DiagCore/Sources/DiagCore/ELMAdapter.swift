import Foundation

public struct AdapterInfo: Equatable, Sendable {
    public var firmware: String
    public var voltage: String
    public var protocolName: String
    public var isCAN: Bool
}

/// Result of a diagnostic request, with negative responses decoded.
public enum DiagResult: Equatable, Sendable {
    case positive([UInt8])
    case negative(UInt8)
    case noResponse
    case fault(ELMFault)
}

public typealias ConsoleLogger = @Sendable (_ sent: String, _ received: String) -> Void

/// Owns the ELM command sequence. Callers must run one job at a time, since the
/// CAN header state is shared between commands.
public actor ELMAdapter {
    private let link: ELMLink
    private var logger: ConsoleLogger?
    public private(set) var info: AdapterInfo?
    private var protocolNumber = "6"

    public init(link: ELMLink) {
        self.link = link
    }

    public func setLogger(_ logger: ConsoleLogger?) {
        self.logger = logger
    }

    @discardableResult
    public func at(_ command: String, timeout: TimeInterval = 2) async throws -> String {
        let response = try await link.command(command, timeout: timeout)
        logger?(command, response)
        return response
    }

    /// Resets the adapter and finds the car's protocol.
    public func initialize() async throws -> AdapterInfo {
        try await at("ATZ", timeout: 3)
        for command in ["ATE0", "ATL0", "ATS0", "ATH0", "ATAT1", "ATAL"] {
            try await at(command)
        }
        let firmware = clean(try await at("ATI"))
        let result = try await connectOBD()
        let voltage = try await batteryVoltage()
        let info = AdapterInfo(firmware: firmware, voltage: voltage, protocolName: result.name, isCAN: result.isCAN)
        self.info = info
        return info
    }

    private func connectOBD() async throws -> (name: String, isCAN: Bool) {
        try await at("ATSP0")
        var reply = try await request([0x01, 0x00], timeout: 12)
        if case .fault = reply {
            // Automatic search failed: Renault diagnostics are CAN 500k on all recent cars.
            try await at("ATSP6")
            reply = try await request([0x01, 0x00], timeout: 4)
        }
        if case .fault(let fault) = reply { throw AdapterError.car(fault.rawValue) }
        if case .noData = reply { throw AdapterError.car(ELMFault.unableToConnect.rawValue) }
        let number = clean(try await at("ATDPN")).replacingOccurrences(of: "A", with: "")
        let name = clean(try await at("ATDP"))
        let isCAN = ["6", "7", "8", "9"].contains(number)
        if isCAN {
            protocolNumber = number
            try await useOBDAddressing()
        }
        return (name, isCAN)
    }

    /// Restores legislated OBD addressing (only the engine ECU answers).
    public func useOBDAddressing() async throws {
        guard info?.isCAN ?? true else {
            // Car found on K-Line: drop the manual headers and let the adapter search again.
            for command in ["ATD", "ATE0", "ATL0", "ATS0", "ATH0", "ATAL", "ATSP0"] {
                try await at(command)
            }
            return
        }
        try await at("ATSP\(protocolNumber)")
        try await at("ATCAF1")
        try await at("ATSH7DF")
        try await at("ATFCSM0")
        try await at("ATCRA7E8")
        try await at("ATSTFF")
        try await at("ATAT1")
    }

    /// Addresses a single ECU directly on CAN. Renault response IDs are not
    /// request+8, so flow control has to be set by hand.
    public func useECU(_ ecu: RenaultECU, responseTimeoutMs: Int) async throws {
        try await at("ATSP6")
        try await at("ATCAF1")
        try await at("ATAL")
        try await at("ATSH\(ecu.tx)")
        try await at("ATFCSH\(ecu.tx)")
        try await at("ATFCSD300000")
        try await at("ATFCSM1")
        try await at("ATCRA\(ecu.rx)")
        try await at("ATAT0")
        try await at(String(format: "ATST%02X", min(max(responseTimeoutMs / 4, 1), 255)))
    }

    /// Addresses an ECU on K-Line (older Renault), sequence as used by DDT4All.
    public func useKLine(address: String) async throws -> Bool {
        try await at("ATSH81\(address)F1")
        try await at("ATSW96")
        try await at("ATWM81\(address)F13E")
        try await at("ATIB10")
        try await at("ATSP5")
        try await at("ATSTFF")
        let initResponse = try await at("ATFI", timeout: 5)
        return initResponse.uppercased().contains("OK")
    }

    public func batteryVoltage() async throws -> String {
        clean(try await at("ATRV"))
    }

    public func request(_ bytes: [UInt8], timeout: TimeInterval = 3) async throws -> ELMReply {
        let text = hexString(bytes)
        var reply = ELMParser.parse(try await at(text, timeout: timeout))
        // "Response pending" (7F xx 78): the ECU is working, wait and read again.
        for _ in 0..<5 {
            guard case .messages(let messages) = reply else { break }
            let useful = messages.filter { !isPending($0) }
            if !useful.isEmpty {
                reply = .messages(useful)
                break
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            reply = ELMParser.parse(try await at(text, timeout: timeout))
        }
        return reply
    }

    /// Sends a request and matches the reply to its service (SID+0x40, or 7F SID NRC).
    public func diagnostic(_ bytes: [UInt8], timeout: TimeInterval = 3) async throws -> DiagResult {
        switch try await request(bytes, timeout: timeout) {
        case .noData:
            return .noResponse
        case .fault(let fault):
            return .fault(fault)
        case .messages(let messages):
            let sid = bytes[0]
            for message in messages {
                if message.first == sid &+ 0x40 { return .positive(message) }
                if message.count >= 3, message[0] == 0x7F, message[1] == sid { return .negative(message[2]) }
            }
            return .noResponse
        }
    }

    private func isPending(_ message: [UInt8]) -> Bool {
        message.count >= 3 && message[0] == 0x7F && message[2] == 0x78
    }

    private func clean(_ response: String) -> String {
        response
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\0", with: "")
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "OK" }
            .joined(separator: " ")
    }
}

public enum AdapterError: Error, LocalizedError {
    case car(String)

    public var errorDescription: String? {
        switch self {
        case .car(let message): return message
        }
    }
}

public enum NegativeResponse {
    public static func describe(_ code: UInt8) -> String {
        switch code {
        case 0x10: return "Refus général du calculateur"
        case 0x11: return "Service non supporté"
        case 0x12: return "Sous-fonction non supportée"
        case 0x13: return "Format de requête invalide"
        case 0x21: return "Calculateur occupé, réessaie"
        case 0x22: return "Conditions non remplies (contact mis, moteur coupé ?)"
        case 0x31: return "Valeur hors plage"
        case 0x33: return "Accès sécurisé refusé"
        case 0x7E, 0x7F: return "Non disponible dans cette session"
        case 0x81: return "Régime moteur trop élevé"
        case 0x83: return "Moteur en marche : coupe le moteur"
        case 0x84: return "Moteur à l'arrêt : démarre le moteur"
        case 0x88: return "Vitesse véhicule trop élevée"
        case 0x92: return "Tension trop élevée"
        case 0x93: return "Tension trop basse : batterie faible"
        default: return String(format: "Refus du calculateur (code %02X)", code)
        }
    }
}
