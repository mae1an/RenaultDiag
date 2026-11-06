import Foundation

/// A fault code as read from an ECU. `code` is the standard form (P0401),
/// `raw` keeps the exact bytes for lookup in Renault documentation.
public struct DTC: Identifiable, Hashable, Codable, Sendable {
    public var id: String { raw }
    public var code: String
    public var raw: String
    public var failureType: UInt8?
    public var status: UInt8?
    /// Known only for UDS ECUs. KWP status bits are not published per ECU.
    public var isPresent: Bool?

    public var description: String { DTCDictionary.describe(code) }

    public var failureDescription: String? {
        guard let failureType, failureType != 0 else { return nil }
        return DTCDictionary.failureType(failureType)
    }
}

public enum DTCDecoder {
    public static func standardCode(high: UInt8, low: UInt8) -> String {
        let letter = ["P", "C", "B", "U"][Int(high >> 6)]
        return String(format: "%@%d%X%02X", letter, Int((high >> 4) & 0x03), Int(high & 0x0F), Int(low))
    }

    /// Reply to 19 02 mask: `59 02 mask [h l ftb status]…`
    public static func uds(_ bytes: [UInt8]) -> [DTC] {
        guard bytes.count >= 3 else { return [] }
        return stride(from: 3, to: bytes.count - 3, by: 4).compactMap { index in
            let (h, l, ftb, status) = (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
            guard h != 0 || l != 0 || ftb != 0 else { return nil }
            return DTC(
                code: standardCode(high: h, low: l),
                raw: hexString([h, l, ftb]),
                failureType: ftb,
                status: status,
                isPresent: status & 0x01 != 0
            )
        }
    }

    /// Reply to 17/18: `57|58 count entries…`. Entry size varies by ECU (3 or 4
    /// bytes), so it is worked out from the announced count.
    public static func kwp(_ bytes: [UInt8]) -> [DTC] {
        guard bytes.count >= 2 else { return [] }
        let count = Int(bytes[1])
        let payload = Array(bytes.dropFirst(2))
        guard count > 0, !payload.isEmpty else { return [] }
        let computed = payload.count / count
        let size = (computed == 3 || computed == 4) && payload.count % count == 0 ? computed : 3

        return stride(from: 0, to: payload.count - size + 1, by: size).compactMap { index in
            let entry = Array(payload[index..<(index + size)])
            guard entry[0] != 0 || entry[1] != 0 else { return nil }
            return DTC(
                code: standardCode(high: entry[0], low: entry[1]),
                raw: hexString(Array(entry.dropLast())),
                failureType: size == 4 ? entry[2] : nil,
                status: entry.last,
                isPresent: nil
            )
        }
    }

    /// Legislated OBD reply (modes 03/07/0A). CAN adds a count byte after the service.
    public static func obd(_ messages: [[UInt8]], isCAN: Bool) -> [DTC] {
        var bytes: [UInt8] = []
        for message in messages {
            bytes += message.dropFirst(isCAN ? 2 : 1)
        }
        return stride(from: 0, to: bytes.count - 1, by: 2).compactMap { index in
            let (h, l) = (bytes[index], bytes[index + 1])
            guard h != 0 || l != 0 else { return nil }
            return DTC(code: standardCode(high: h, low: l), raw: hexString([h, l]), failureType: nil, status: nil, isPresent: nil)
        }
    }
}
