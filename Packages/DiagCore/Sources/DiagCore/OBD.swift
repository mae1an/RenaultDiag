import Foundation

public struct PID: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case engine = "Moteur"
        case air = "Air et turbo"
        case fuel = "Carburant"
        case emissions = "Émissions"
        case exhaust = "Échappement et FAP"
        case vehicle = "Véhicule"
    }

    /// Key of the measure in the app. Equals the OBD PID, except when one PID
    /// carries several sensors: those extra sensors use keys from 0xC0 up.
    public let id: UInt8
    /// The OBD PID to send to read this measure.
    public let request: UInt8
    public let name: String
    public let unit: String
    public let range: ClosedRange<Double>
    public let group: Group
    let decode: @Sendable ([Double]) -> Double

    init(id: UInt8, request: UInt8? = nil, name: String, unit: String, range: ClosedRange<Double>, group: Group, decode: @escaping @Sendable ([Double]) -> Double) {
        self.id = id
        self.request = request ?? id
        self.name = name
        self.unit = unit
        self.range = range
        self.group = group
        self.decode = decode
    }

    public static func == (lhs: PID, rhs: PID) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public func value(from bytes: [UInt8]) -> Double? {
        guard !bytes.isEmpty else { return nil }
        let value = decode(bytes.map(Double.init))
        return value.isNaN ? nil : value
    }
}

private func word(_ b: [Double]) -> Double { b.count > 1 ? b[0] * 256 + b[1] : b[0] }

/// Multi-sensor PID: byte A flags fitted sensors, then 2 bytes per sensor.
/// Returns NaN when the car says the sensor is absent or the reply is too short.
private func sensor(_ b: [Double], bit: Int, at index: Int, scale: Double, offset: Double = 0, signed: Bool = false) -> Double {
    guard b.count >= index + 2, Int(b[0]) & (1 << bit) != 0 else { return .nan }
    var raw = b[index] * 256 + b[index + 1]
    if signed && raw >= 32768 { raw -= 65536 }
    return raw * scale + offset
}

public enum PIDCatalog {
    public static let all: [PID] = [
        PID(id: 0x0C, name: "Régime moteur", unit: "tr/min", range: 0...7000, group: .engine) { word($0) / 4 },
        PID(id: 0x04, name: "Charge moteur", unit: "%", range: 0...100, group: .engine) { $0[0] * 100 / 255 },
        PID(id: 0x43, name: "Charge absolue", unit: "%", range: 0...200, group: .engine) { word($0) * 100 / 255 },
        PID(id: 0x05, name: "Température liquide", unit: "°C", range: -40...130, group: .engine) { $0[0] - 40 },
        PID(id: 0x5C, name: "Température huile", unit: "°C", range: -40...160, group: .engine) { $0[0] - 40 },
        PID(id: 0x0E, name: "Avance à l'allumage", unit: "°", range: -64...64, group: .engine) { $0[0] / 2 - 64 },
        PID(id: 0x61, name: "Couple demandé", unit: "%", range: -125...125, group: .engine) { $0[0] - 125 },
        PID(id: 0x62, name: "Couple réel", unit: "%", range: -125...125, group: .engine) { $0[0] - 125 },
        PID(id: 0x1F, name: "Temps depuis démarrage", unit: "s", range: 0...7200, group: .engine) { word($0) },

        PID(id: 0x0B, name: "Pression d'admission", unit: "kPa", range: 0...255, group: .air) { $0[0] },
        PID(id: 0x10, name: "Débit d'air", unit: "g/s", range: 0...300, group: .air) { word($0) / 100 },
        PID(id: 0x0F, name: "Température admission", unit: "°C", range: -40...100, group: .air) { $0[0] - 40 },
        PID(id: 0x11, name: "Papillon", unit: "%", range: 0...100, group: .air) { $0[0] * 100 / 255 },
        PID(id: 0x45, name: "Papillon relatif", unit: "%", range: 0...100, group: .air) { $0[0] * 100 / 255 },
        PID(id: 0x49, name: "Pédale d'accélérateur", unit: "%", range: 0...100, group: .air) { $0[0] * 100 / 255 },
        PID(id: 0x33, name: "Pression atmosphérique", unit: "kPa", range: 70...110, group: .air) { $0[0] },

        PID(id: 0x06, name: "Correction court terme", unit: "%", range: -100...100, group: .fuel) { ($0[0] - 128) * 100 / 128 },
        PID(id: 0x07, name: "Correction long terme", unit: "%", range: -100...100, group: .fuel) { ($0[0] - 128) * 100 / 128 },
        PID(id: 0x23, name: "Pression de rampe", unit: "bar", range: 0...2000, group: .fuel) { word($0) * 10 / 100 },
        PID(id: 0x2F, name: "Niveau de carburant", unit: "%", range: 0...100, group: .fuel) { $0[0] * 100 / 255 },
        PID(id: 0x5E, name: "Consommation", unit: "L/h", range: 0...50, group: .fuel) { word($0) / 20 },
        PID(id: 0x44, name: "Lambda demandé", unit: "λ", range: 0...2, group: .fuel) { word($0) / 32768 },

        PID(id: 0x2C, name: "EGR commandée", unit: "%", range: 0...100, group: .emissions) { $0[0] * 100 / 255 },
        PID(id: 0x2D, name: "Erreur EGR", unit: "%", range: -100...100, group: .emissions) { ($0[0] - 128) * 100 / 128 },
        PID(id: 0x3C, name: "Température catalyseur", unit: "°C", range: -40...1000, group: .emissions) { word($0) / 10 - 40 },
        PID(id: 0x2E, name: "Purge canister", unit: "%", range: 0...100, group: .emissions) { $0[0] * 100 / 255 },
        PID(id: 0x30, name: "Démarrages depuis effacement", unit: "", range: 0...255, group: .emissions) { $0[0] },
        PID(id: 0x31, name: "Distance depuis effacement", unit: "km", range: 0...65535, group: .emissions) { word($0) },
        PID(id: 0x21, name: "Distance voyant allumé", unit: "km", range: 0...65535, group: .emissions) { word($0) },

        PID(id: 0x7A, name: "Pression différentielle FAP", unit: "kPa", range: -50...100, group: .exhaust) { sensor($0, bit: 0, at: 1, scale: 0.01, signed: true) },
        PID(id: 0xC5, request: 0x7A, name: "Pression entrée FAP", unit: "kPa", range: 0...655, group: .exhaust) { sensor($0, bit: 1, at: 3, scale: 0.01) },
        PID(id: 0xC6, request: 0x7A, name: "Pression sortie FAP", unit: "kPa", range: 0...655, group: .exhaust) { sensor($0, bit: 2, at: 5, scale: 0.01) },
        PID(id: 0x73, name: "Pression d'échappement", unit: "kPa", range: 0...655, group: .exhaust) { sensor($0, bit: 0, at: 1, scale: 0.01) },
        PID(id: 0x7C, name: "Température entrée FAP", unit: "°C", range: -40...1000, group: .exhaust) { sensor($0, bit: 0, at: 1, scale: 0.1, offset: -40) },
        PID(id: 0xC7, request: 0x7C, name: "Température sortie FAP", unit: "°C", range: -40...1000, group: .exhaust) { sensor($0, bit: 1, at: 3, scale: 0.1, offset: -40) },
        PID(id: 0xC1, request: 0x78, name: "Température gaz, sonde 1", unit: "°C", range: -40...1000, group: .exhaust) { sensor($0, bit: 0, at: 1, scale: 0.1, offset: -40) },
        PID(id: 0xC2, request: 0x78, name: "Température gaz, sonde 2", unit: "°C", range: -40...1000, group: .exhaust) { sensor($0, bit: 1, at: 3, scale: 0.1, offset: -40) },
        PID(id: 0xC3, request: 0x78, name: "Température gaz, sonde 3", unit: "°C", range: -40...1000, group: .exhaust) { sensor($0, bit: 2, at: 5, scale: 0.1, offset: -40) },
        PID(id: 0xC4, request: 0x78, name: "Température gaz, sonde 4", unit: "°C", range: -40...1000, group: .exhaust) { sensor($0, bit: 3, at: 7, scale: 0.1, offset: -40) },

        PID(id: 0x0D, name: "Vitesse", unit: "km/h", range: 0...220, group: .vehicle) { $0[0] },
        PID(id: 0x42, name: "Tension calculateur", unit: "V", range: 0...18, group: .vehicle) { word($0) / 1000 },
        PID(id: 0x46, name: "Température extérieure", unit: "°C", range: -40...60, group: .vehicle) { $0[0] - 40 },
    ]

    public static func pid(_ id: UInt8) -> PID? { all.first { $0.id == id } }
}

public struct Monitor: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let complete: Bool
}

public struct VehicleStatus: Sendable, Equatable {
    public var milOn: Bool
    public var storedCount: Int
    public var isDiesel: Bool
    /// From the fuel type PID. Some diesels report the spark-ignition flag in
    /// PID 01, so that flag is never shown to the user as the engine type.
    public var fuelName: String?
    public var monitors: [Monitor]
}

public struct FreezeFrame: Sendable, Equatable {
    public var cause: String?
    public var values: [(name: String, value: String)]

    public static func == (lhs: FreezeFrame, rhs: FreezeFrame) -> Bool {
        lhs.cause == rhs.cause && lhs.values.map(\.name) == rhs.values.map(\.name) && lhs.values.map(\.value) == rhs.values.map(\.value)
    }
}

public struct OBDService: Sendable {
    public let adapter: ELMAdapter
    public init(adapter: ELMAdapter) { self.adapter = adapter }

    public func supportedPIDs() async throws -> Set<UInt8> {
        var supported = Set<UInt8>()
        for base: UInt8 in [0x00, 0x20, 0x40, 0x60] {
            guard case .positive(let bytes) = try await adapter.diagnostic([0x01, base]), bytes.count >= 6 else { break }
            for byteIndex in 0..<4 {
                for bit in 0..<8 where bytes[2 + byteIndex] & (0x80 >> UInt8(bit)) != 0 {
                    supported.insert(base + UInt8(byteIndex * 8 + bit) + 1)
                }
            }
            if bytes[5] & 0x01 == 0 { break }
        }
        return supported
    }

    public func read(_ pid: PID) async throws -> Double? {
        guard case .positive(let bytes) = try await adapter.diagnostic([0x01, pid.request]),
              bytes.count > 2, bytes[1] == pid.request else { return nil }
        return pid.value(from: Array(bytes.dropFirst(2)))
    }

    public func dtcs(mode: UInt8) async throws -> [DTC] {
        guard case .messages(let messages) = try await adapter.request([mode], timeout: 4) else { return [] }
        let isCAN = await adapter.info?.isCAN ?? true
        return DTCDecoder.obd(messages.filter { $0.first == mode &+ 0x40 }, isCAN: isCAN)
    }

    /// Mode 04: clears engine codes, freeze frame and readiness monitors.
    public func clearEngine() async throws -> DiagResult {
        try await adapter.diagnostic([0x04], timeout: 6)
    }

    public func status() async throws -> VehicleStatus? {
        guard case .positive(let bytes) = try await adapter.diagnostic([0x01, 0x01]), bytes.count >= 6 else { return nil }
        let (a, b, c, d) = (bytes[2], bytes[3], bytes[4], bytes[5])
        var isDiesel = b & 0x08 != 0
        var fuelName: String?
        if case .positive(let fuel) = try await adapter.diagnostic([0x01, 0x51]), fuel.count >= 3 {
            if fuel[2] == 0x04 { isDiesel = true }
            fuelName = [0x01: "Essence", 0x04: "Diesel"][fuel[2]]
        }
        var monitors: [Monitor] = []

        func add(_ name: String, supported: Bool, incomplete: Bool) {
            if supported { monitors.append(Monitor(name: name, complete: !incomplete)) }
        }
        add("Ratés d'allumage", supported: b & 0x01 != 0, incomplete: b & 0x10 != 0)
        add("Alimentation", supported: b & 0x02 != 0, incomplete: b & 0x20 != 0)
        add("Composants", supported: b & 0x04 != 0, incomplete: b & 0x40 != 0)

        let names = isDiesel
            ? ["Catalyseur NMHC", "Catalyseur NOx", "", "Pression de suralimentation", "", "Sonde de gaz", "Filtre à particules", "EGR / VVT"]
            : ["Catalyseur", "Catalyseur chauffé", "Circuit d'évaporation", "Air secondaire", "", "Sonde lambda", "Chauffage sonde", "EGR / VVT"]
        for (bit, name) in names.enumerated() where !name.isEmpty {
            let mask = UInt8(1) << UInt8(bit)
            add(name, supported: c & mask != 0, incomplete: d & mask != 0)
        }
        return VehicleStatus(milOn: a & 0x80 != 0, storedCount: Int(a & 0x7F), isDiesel: isDiesel, fuelName: fuelName, monitors: monitors)
    }

    public func vin() async throws -> String? {
        guard case .messages(let messages) = try await adapter.request([0x09, 0x02], timeout: 4) else { return nil }
        let bytes = messages.filter { $0.first == 0x49 }.flatMap { $0.dropFirst(2) }
        let text = String(bytes.filter { (48...90).contains($0) }.map { Character(UnicodeScalar($0)) })
        return text.count >= 17 ? String(text.suffix(17)) : nil
    }

    /// Conditions recorded when the engine fault was stored (mode 02, frame 0).
    public func freezeFrame() async throws -> FreezeFrame? {
        guard case .positive(let cause) = try await adapter.diagnostic([0x02, 0x02, 0x00]),
              cause.count >= 5, cause[3] != 0 || cause[4] != 0 else { return nil }
        var values: [(name: String, value: String)] = []
        for id: UInt8 in [0x0C, 0x0D, 0x05, 0x04, 0x0B, 0x10, 0x0F, 0x42] {
            guard let pid = PIDCatalog.pid(id),
                  case .positive(let bytes) = try await adapter.diagnostic([0x02, id, 0x00]),
                  bytes.count > 3,
                  let value = pid.value(from: Array(bytes.dropFirst(3))) else { continue }
            values.append((pid.name, "\(formatted(value)) \(pid.unit)"))
        }
        return FreezeFrame(cause: DTCDecoder.standardCode(high: cause[3], low: cause[4]), values: values)
    }
}

public func formatted(_ value: Double) -> String {
    abs(value) >= 100 || value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
}
