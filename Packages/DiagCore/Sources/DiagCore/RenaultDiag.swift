import Foundation

/// One Renault ECU on the diagnostic CAN bus.
public struct RenaultECU: Identifiable, Hashable, Sendable {
    public let address: String
    public let tx: String
    public let rx: String
    public let name: String
    /// True for older ECUs reached on K-Line (pin 7) instead of CAN.
    public var isKLine = false
    public var id: String { isKLine ? "K" + address : address }
}

public enum RenaultNetwork {
    /// Names we are confident of. Everything else is reported by its address.
    private static let names: [String: String] = [
        "7A": "Moteur (injection)",
        "6E": "Boîte automatique",
        "01": "ABS / ESP",
        "2C": "Airbag",
        "26": "UCH (habitacle)",
        "51": "Tableau de bord",
        "04": "Direction assistée",
        "0D": "Frein de parking",
        "29": "Climatisation",
        "27": "UPC (boîtier moteur)",
        "57": "Radio / multimédia",
    ]

    /// 11-bit address translation table, from the pyren project.
    private static let tx: [String: String] = [
        "01":"740","02":"704","04":"742","06":"790","07":"751","08":"758","09":"7E3",
        "0D":"755","0E":"74E","0F":"750","11":"7C3","12":"7C9","13":"712","1A":"711",
        "1B":"7A4","1C":"74B","1E":"748","23":"753","24":"75D","25":"70C","26":"745",
        "27":"74D","28":"78A","29":"744","2A":"74F","2B":"723","2C":"752","2E":"79C",
        "2F":"74C","32":"756","3A":"7D6","3C":"7D9","40":"707","46":"7CD",
        "47":"788","4D":"79D","50":"718","51":"743","57":"747","59":"714",
        "5B":"785","61":"7B7","62":"7DC","63":"73D",
        "64":"7D4","66":"719","67":"792","68":"75A","6B":"795","6E":"7E1","77":"7CA",
        "79":"7E2","7A":"7E0","7C":"75C","81":"73F","82":"7AA",
        "86":"782","87":"780","91":"7E5","93":"79B","95":"7E4","97":"7D8",
        "A5":"705","A6":"706","A7":"713","A8":"796","C0":"799","D1":"7E6",
        "DE":"6BC","DF":"641","E0":"60B","E1":"63A","E2":"63B","E3":"73A",
        "E6":"622","E8":"644","EA":"79A","EB":"638","EC":"637","F7":"716","F8":"717","FA":"75B",
    ]

    private static let rx: [String: String] = [
        "01":"760","02":"724","04":"762","06":"791","07":"771","08":"778","09":"7EB",
        "0D":"775","0E":"76E","0F":"770","11":"7C9","12":"7C3","13":"732","1A":"731",
        "1B":"7AC","1C":"76B","1E":"768","23":"773","24":"77D","25":"700","26":"765",
        "27":"76D","28":"7D7","29":"764","2A":"76F","2B":"735","2C":"772","2E":"7BC",
        "2F":"76C","32":"776","3A":"7D2","3C":"7DB","40":"727","46":"7CF","47":"7A8",
        "4D":"7BD","50":"738","51":"763","57":"767","59":"734","5B":"7A5",
        "61":"7BA","62":"7DD","63":"73E","64":"7D5",
        "66":"739","67":"793","68":"77E","6B":"7B5","6E":"7E9","77":"7DA",
        "79":"7EA","7A":"7E8","7C":"77C","81":"761","82":"7AD","86":"7A2",
        "87":"7A0","91":"7ED","93":"7BB","95":"7EC","97":"7C8",
        "A5":"725","A6":"726","A7":"733","A8":"7B6","C0":"7B9","D1":"7EE",
        "DE":"69C","DF":"5C1","E0":"58B","E1":"5BA","E2":"5BB","E3":"4A7",
        "E6":"484","E8":"5C4","EA":"4B3","EB":"5B8","EC":"5B7","F7":"736","F8":"737","FA":"77B",
    ]

    /// Main ECUs first so the useful answers show up early during a scan.
    public static let allECUs: [RenaultECU] = {
        let priority = ["7A", "6E", "01", "2C", "26", "51", "04", "0D", "29", "27", "57"]
        let others = tx.keys.filter { !priority.contains($0) }.sorted()
        return (priority + others).compactMap { address in
            guard let txID = tx[address], let rxID = rx[address] else { return nil }
            return RenaultECU(address: address, tx: txID, rx: rxID, name: names[address] ?? "Calculateur \(address)")
        }
    }()

    public static let mainECUs: [RenaultECU] = Array(allECUs.prefix(names.count))

    /// The same main ECUs, reached on K-Line. Slow to probe (about 3 s each), so only on request.
    public static let kLineECUs: [RenaultECU] = mainECUs.map {
        RenaultECU(address: $0.address, tx: "", rx: "", name: $0.name, isKLine: true)
    }
}

public enum DTCReadMethod: String, Codable, Sendable {
    case uds19 = "UDS 19 02"
    case kwp17 = "KWP 17 FF 00"
    case kwp18 = "KWP 18 00 FF 00"
}

public struct ECUReport: Identifiable, Sendable, Codable, Equatable {
    public var id: String { isKLine ? "K" + address : address }
    public var address: String
    public var name: String
    public var isKLine = false
    public var identification: String?
    public var method: DTCReadMethod?
    public var dtcs: [DTC]
    public var readError: String?
}

public struct ClearOutcome: Sendable, Equatable {
    public var accepted: Bool
    public var message: String
    public var remaining: [DTC]
}

/// Direct, per-ECU diagnostics: read and clear, nothing that writes configuration.
public struct RenaultDiagnostics: Sendable {
    public let adapter: ELMAdapter

    public init(adapter: ELMAdapter) {
        self.adapter = adapter
    }

    /// Scans a list of ECUs and yields a report for each one that answers.
    public func scan(
        _ ecus: [RenaultECU],
        progress: @Sendable @escaping (_ done: Int, _ total: Int, _ current: RenaultECU) -> Void,
        found: @Sendable @escaping (ECUReport) -> Void
    ) async throws {
        for (index, ecu) in ecus.enumerated() {
            try Task.checkCancellation()
            progress(index, ecus.count, ecu)
            if let report = try await read(ecu, probeTimeoutMs: 150) {
                found(report)
            }
        }
        progress(ecus.count, ecus.count, ecus.last!)
        try await adapter.useOBDAddressing()
    }

    /// Returns nil when the ECU does not answer.
    public func read(_ ecu: RenaultECU, probeTimeoutMs: Int = 400) async throws -> ECUReport? {
        guard try await select(ecu, responseTimeoutMs: probeTimeoutMs),
              let session = try await openSession() else { return nil }

        // Replies can be long and slow once we know the ECU is there.
        try await adapter.at("ATST\(String(format: "%02X", 200))")
        let identification = try await readIdentification()
        var report = ECUReport(address: ecu.address, name: ecu.name, isKLine: ecu.isKLine, identification: identification, method: nil, dtcs: [], readError: nil)

        do {
            let (method, dtcs) = try await readDTCs()
            report.method = method
            report.dtcs = dtcs
        } catch let error as DTCReadError {
            report.readError = error.message
        }
        try await closeSession(session)
        return report
    }

    /// Clears one ECU's fault memory, then re-reads it: anything left is a real, present fault.
    public func clear(_ ecu: RenaultECU, method: DTCReadMethod?) async throws -> ClearOutcome {
        guard try await select(ecu, responseTimeoutMs: 800), let session = try await openSession() else {
            try await adapter.useOBDAddressing()
            return ClearOutcome(accepted: false, message: "Le calculateur ne répond plus.", remaining: [])
        }

        // UDS uses a 3-byte group, KWP a 2-byte one. Start with what the read used.
        let udsClear: [UInt8] = [0x14, 0xFF, 0xFF, 0xFF]
        let kwpClear: [UInt8] = [0x14, 0xFF, 0x00]
        let attempts = method == .uds19 ? [udsClear, kwpClear] : [kwpClear, udsClear]

        var lastRefusal: UInt8?
        var accepted = false
        for request in attempts {
            switch try await adapter.diagnostic(request, timeout: 6) {
            case .positive:
                accepted = true
            case .negative(let code):
                lastRefusal = code
            case .noResponse, .fault:
                break
            }
            if accepted { break }
            // A refusal for a condition (ignition, voltage) will not change with another format.
            if let code = lastRefusal, ![0x11, 0x12, 0x13, 0x31, 0x7E, 0x7F].contains(code) { break }
        }

        guard accepted else {
            try await closeSession(session)
            try await adapter.useOBDAddressing()
            let reason = lastRefusal.map(NegativeResponse.describe) ?? "Pas de réponse à la commande d'effacement."
            return ClearOutcome(accepted: false, message: reason, remaining: [])
        }

        try await Task.sleep(nanoseconds: 1_500_000_000)
        let remaining = (try? await readDTCs().1) ?? []
        try await closeSession(session)
        try await adapter.useOBDAddressing()

        let message = remaining.isEmpty
            ? "Mémoire effacée, aucun défaut ne revient pour l'instant."
            : "Effacement accepté, mais \(remaining.count) défaut(s) reviennent aussitôt : la panne est toujours là."
        return ClearOutcome(accepted: true, message: message, remaining: remaining)
    }

    private func select(_ ecu: RenaultECU, responseTimeoutMs: Int) async throws -> Bool {
        if ecu.isKLine { return try await adapter.useKLine(address: ecu.address) }
        try await adapter.useECU(ecu, responseTimeoutMs: responseTimeoutMs)
        return true
    }

    enum Session { case renault, uds, none }

    func openSession() async throws -> Session? {
        switch try await adapter.diagnostic([0x10, 0xC0]) {
        case .positive:
            return .renault
        case .noResponse, .fault:
            return nil
        case .negative:
            if case .positive = try await adapter.diagnostic([0x10, 0x03]) { return .uds }
            return Session.none
        }
    }

    private func closeSession(_ session: Session) async throws {
        switch session {
        case .renault: _ = try await adapter.diagnostic([0x10, 0x81])
        case .uds: _ = try await adapter.diagnostic([0x10, 0x01])
        case .none: break
        }
    }

    private func readIdentification() async throws -> String? {
        for request: [UInt8] in [[0x22, 0xF1, 0x87], [0x21, 0x80]] {
            if case .positive(let bytes) = try await adapter.diagnostic(request) {
                let printable: [Character] = bytes[min(request.count, bytes.count)...].map { (32...126).contains($0) ? Character(UnicodeScalar($0)) : " " }
                let words: [Substring] = String(printable).split(separator: " ")
                let text = words.filter { $0.count >= 4 }.joined(separator: " ")
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private struct DTCReadError: Error {
        let message: String
    }

    private func readDTCs() async throws -> (DTCReadMethod, [DTC]) {
        var refusal: UInt8?
        var answered = false

        switch try await adapter.diagnostic([0x19, 0x02, 0xAF], timeout: 4) {
        case .positive(let bytes): return (.uds19, DTCDecoder.uds(bytes))
        case .negative(let code): refusal = code; answered = true
        default: break
        }
        switch try await adapter.diagnostic([0x17, 0xFF, 0x00], timeout: 4) {
        case .positive(let bytes): return (.kwp17, DTCDecoder.kwp(bytes))
        case .negative(let code): refusal = code; answered = true
        default: break
        }
        switch try await adapter.diagnostic([0x18, 0x00, 0xFF, 0x00], timeout: 4) {
        case .positive(let bytes): return (.kwp18, DTCDecoder.kwp(bytes))
        case .negative(let code): refusal = code; answered = true
        default: break
        }

        if answered, let refusal {
            throw DTCReadError(message: NegativeResponse.describe(refusal))
        }
        throw DTCReadError(message: "Pas de réponse à la lecture des défauts.")
    }
}
