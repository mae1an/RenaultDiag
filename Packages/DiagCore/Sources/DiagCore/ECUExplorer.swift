import Foundation

/// A value an ECU agreed to give, tracked over time to see which bytes move.
public struct ECUValue: Identifiable, Sendable, Equatable {
    public var id: String { hexString(request) }
    public let request: [UInt8]
    public private(set) var latest: [UInt8]
    public private(set) var low: [UInt8]
    public private(set) var high: [UInt8]

    public init(request: [UInt8], reply: [UInt8]) {
        self.request = request
        latest = reply
        low = reply
        high = reply
    }

    public mutating func update(_ reply: [UInt8]) {
        guard reply.count == latest.count else { latest = reply; low = reply; high = reply; return }
        latest = reply
        low = zip(low, reply).map(min)
        high = zip(high, reply).map(max)
    }

    public var changingBytes: Int { zip(low, high).filter { $0 != $1 }.count }
}

/// Finds which identifiers an ECU answers to. Read services only: this never
/// sends anything that could change the ECU.
public struct ECUExplorer: Sendable {
    public let adapter: ELMAdapter
    private let diagnostics: RenaultDiagnostics

    public init(adapter: ELMAdapter) {
        self.adapter = adapter
        diagnostics = RenaultDiagnostics(adapter: adapter)
    }

    /// KWP local identifiers, identification data, then the 20xx-2Fxx UDS range.
    public static let standardRequests: [[UInt8]] = {
        let kwp = (0x01...0xFF).map { [UInt8(0x21), UInt8($0)] }
        let identification = (0x00...0xFF).map { [UInt8(0x22), UInt8(0xF1), UInt8($0)] }
        let data = (0x2000...0x2FFF).map { [UInt8(0x22), UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        return kwp + identification + data
    }()

    public static func isReadOnly(_ request: [UInt8]) -> Bool {
        (request.first == 0x21 && request.count == 2) || (request.first == 0x22 && request.count == 3)
    }

    /// Returns false when the ECU does not answer.
    public func open(_ ecu: RenaultECU) async throws -> Bool {
        try await adapter.useECU(ecu, responseTimeoutMs: 200)
        return try await diagnostics.openSession() != nil
    }

    public func close() async throws {
        _ = try await adapter.diagnostic([0x10, 0x81])
        try await adapter.useOBDAddressing()
    }

    public func search(
        _ requests: [[UInt8]],
        progress: @Sendable (_ done: Int, _ total: Int) -> Void,
        found: @Sendable (ECUValue) -> Void
    ) async throws {
        let safe = requests.filter(Self.isReadOnly)
        for (index, request) in safe.enumerated() {
            try Task.checkCancellation()
            if index % 40 == 0 {
                progress(index, safe.count)
                try await keepAlive()
            }
            if let reply = try await read(request) {
                found(ECUValue(request: request, reply: reply))
            }
        }
        progress(safe.count, safe.count)
    }

    public func read(_ request: [UInt8]) async throws -> [UInt8]? {
        guard Self.isReadOnly(request),
              case .positive(let bytes) = try await adapter.diagnostic(request) else { return nil }
        return bytes
    }

    public func keepAlive() async throws {
        _ = try await adapter.diagnostic([0x3E, 0x00])
    }

    /// Engine speed, sent to the same ECU, to line it up with the unknown values.
    public func engineSpeed() async throws -> Double? {
        guard case .positive(let bytes) = try await adapter.diagnostic([0x01, 0x0C]), bytes.count >= 4 else { return nil }
        return PIDCatalog.pid(0x0C)?.value(from: Array(bytes.dropFirst(2)))
    }
}
