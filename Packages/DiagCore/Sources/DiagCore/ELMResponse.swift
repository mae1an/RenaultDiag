import Foundation

/// Transport to an ELM327-compatible adapter: sends one command, returns the
/// raw text received up to the `>` prompt. Implemented by BLE and by the simulator.
public protocol ELMLink: Sendable {
    func command(_ text: String, timeout: TimeInterval) async throws -> String
}

public enum LinkError: Error, LocalizedError, Equatable {
    case timeout
    case disconnected
    case bluetooth(String)

    public var errorDescription: String? {
        switch self {
        case .timeout: return "L'adaptateur ne répond pas."
        case .disconnected: return "Adaptateur déconnecté."
        case .bluetooth(let message): return message
        }
    }
}

public enum ELMFault: String, Equatable, Sendable {
    case unableToConnect = "Impossible de joindre la voiture. Le contact est-il mis ?"
    case canError = "Erreur sur le bus CAN."
    case busInitError = "Échec d'initialisation du bus."
    case busBusy = "Bus occupé."
    case dataError = "Données corrompues."
    case bufferFull = "Tampon de l'adaptateur plein."
    case stopped = "Requête interrompue."
    case lowVoltage = "Tension trop basse : l'adaptateur a redémarré."
    case unknownCommand = "Commande refusée par l'adaptateur."
}

public enum ELMReply: Equatable, Sendable {
    case messages([[UInt8]])
    case noData
    case fault(ELMFault)
}

public enum ELMParser {
    /// Parses the ELM327 text output with headers off (ATH0).
    /// Handles single frames, CAN multi-frame ("014", "0:…", "1:…"), and
    /// several responders on separate lines.
    public static func parse(_ raw: String) -> ELMReply {
        let lines = raw
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: ">", with: "")
            .uppercased()
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { $0.replacingOccurrences(of: " ", with: "") }
            .filter { !$0.isEmpty }

        var messages: [[UInt8]] = []
        var segments: [Int: [UInt8]] = [:]
        var expectedLength: Int?
        var sawNoData = false

        func flushSegments() {
            guard !segments.isEmpty else { return }
            var joined = segments.keys.sorted().flatMap { segments[$0]! }
            if let expectedLength, joined.count > expectedLength {
                joined = Array(joined.prefix(expectedLength))
            }
            messages.append(joined)
            segments = [:]
            expectedLength = nil
        }

        for line in lines {
            if let fault = fault(in: line) { return .fault(fault) }
            if line.contains("NODATA") { sawNoData = true; continue }
            if line.hasPrefix("SEARCHING") || line.hasPrefix("BUSINIT") { continue }

            if line.count == 3, let length = Int(line, radix: 16) {
                flushSegments()
                expectedLength = length
                continue
            }
            if line.count >= 2, line[line.index(after: line.startIndex)] == ":",
               let index = Int(String(line.first!), radix: 16),
               let bytes = hexBytes(String(line.dropFirst(2))) {
                segments[index] = bytes
                continue
            }
            if let bytes = hexBytes(line) {
                flushSegments()
                messages.append(bytes)
            }
        }
        flushSegments()

        if messages.isEmpty { return sawNoData ? .noData : .noData }
        return .messages(messages)
    }

    private static func fault(in line: String) -> ELMFault? {
        if line == "?" { return .unknownCommand }
        if line.contains("UNABLETOCONNECT") { return .unableToConnect }
        if line.contains("CANERROR") { return .canError }
        if line.contains("BUSINIT") && line.contains("ERROR") { return .busInitError }
        if line.contains("BUSBUSY") { return .busBusy }
        if line.contains("DATAERROR") || line.contains("RXERROR") || line.contains("FBERROR") { return .dataError }
        if line.contains("BUFFERFULL") { return .bufferFull }
        if line.contains("STOPPED") { return .stopped }
        if line.contains("LVRESET") { return .lowVoltage }
        return nil
    }

    public static func hexBytes(_ text: String) -> [UInt8]? {
        guard !text.isEmpty, text.count % 2 == 0 else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }
}

public func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined()
}
