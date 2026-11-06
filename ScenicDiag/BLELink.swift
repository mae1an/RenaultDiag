import CoreBluetooth
import DiagCore
import Foundation

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    var isLikelyAdapter: Bool {
        let lower = name.lowercased()
        return ["vlinker", "vgate", "obd", "elm"].contains { lower.contains($0) }
    }
}

/// BLE serial bridge to the adapter. Its characteristic UUIDs are not documented,
/// so the service with a notify and a write characteristic is found at connection.
/// All Bluetooth state lives on the main queue.
final class BLELink: NSObject, ELMLink, @unchecked Sendable {
    private static let standardServices = ["1800", "1801", "180A", "180F"].map { CBUUID(string: $0) }

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var servicesLeft = 0

    private var buffer = ""
    private var pending: CheckedContinuation<String, Error>?
    private var timeoutWork: DispatchWorkItem?
    private var connectContinuation: CheckedContinuation<String, Error>?

    var onDevice: ((DiscoveredDevice) -> Void)?
    var onStateChange: ((String?) -> Void)?
    var onDisconnect: (() -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
    }

    /// Connects and returns a description of the GATT link for the console.
    func connect(to id: UUID) async throws -> String {
        guard let target = peripherals[id] else { throw LinkError.bluetooth("Appareil introuvable, relance la recherche.") }
        central.stopScan()
        peripheral = target
        target.delegate = self
        return try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            central.connect(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.finishConnect(.failure(LinkError.bluetooth("La connexion a expiré. Le vLinker est-il branché et le contact mis ?")))
            }
        }
    }

    func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        writeCharacteristic = nil
    }

    func command(_ text: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [self] in
                guard let peripheral, let writeCharacteristic, peripheral.state == .connected else {
                    continuation.resume(throwing: LinkError.disconnected)
                    return
                }
                buffer = ""
                pending = continuation

                let type: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
                let data = Data((text + "\r").utf8)
                let chunkSize = max(peripheral.maximumWriteValueLength(for: type), 20)
                var offset = 0
                while offset < data.count {
                    let end = min(offset + chunkSize, data.count)
                    peripheral.writeValue(data.subdata(in: offset..<end), for: writeCharacteristic, type: type)
                    offset = end
                }

                let work = DispatchWorkItem { [weak self] in
                    self?.resolve(.failure(LinkError.timeout))
                }
                timeoutWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
            }
        }
    }

    private func resolve(_ result: Result<String, Error>) {
        timeoutWork?.cancel()
        timeoutWork = nil
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    private func finishConnect(_ result: Result<String, Error>) {
        let continuation = connectContinuation
        connectContinuation = nil
        continuation?.resume(with: result)
    }

    private func selectCharacteristics(on peripheral: CBPeripheral) {
        let services = (peripheral.services ?? []).filter { !Self.standardServices.contains($0.uuid) }

        func find(_ wanted: CBCharacteristicProperties, in service: CBService) -> CBCharacteristic? {
            service.characteristics?.first { !$0.properties.intersection(wanted).isEmpty }
        }
        let writable: CBCharacteristicProperties = [.write, .writeWithoutResponse]
        let notifying: CBCharacteristicProperties = [.notify, .indicate]

        // Prefer a single service offering both directions.
        var pair: (write: CBCharacteristic, notify: CBCharacteristic)?
        for service in services {
            if let write = find(writable, in: service), let notify = find(notifying, in: service) {
                pair = (write, notify)
                break
            }
        }
        if pair == nil,
           let write = services.lazy.compactMap({ find(writable, in: $0) }).first,
           let notify = services.lazy.compactMap({ find(notifying, in: $0) }).first {
            pair = (write, notify)
        }

        guard let pair else {
            finishConnect(.failure(LinkError.bluetooth("Cet appareil n'est pas un adaptateur OBD compatible.")))
            central.cancelPeripheralConnection(peripheral)
            return
        }
        writeCharacteristic = pair.write
        peripheral.setNotifyValue(true, for: pair.notify)
    }
}

extension BLELink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            onStateChange?(nil)
            startScan()
        case .poweredOff: onStateChange?("Le Bluetooth est coupé. Active-le dans Réglages.")
        case .unauthorized: onStateChange?("Autorise le Bluetooth pour RenaultDiag dans Réglages.")
        case .unsupported: onStateChange?("Bluetooth indisponible sur cet appareil. Le mode démo reste utilisable.")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        guard let name, !name.isEmpty else { return }
        peripherals[peripheral.identifier] = peripheral
        onDevice?(DiscoveredDevice(id: peripheral.identifier, name: name, rssi: rssi.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishConnect(.failure(LinkError.bluetooth(error?.localizedDescription ?? "Connexion Bluetooth impossible.")))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resolve(.failure(LinkError.disconnected))
        finishConnect(.failure(LinkError.disconnected))
        writeCharacteristic = nil
        onDisconnect?()
    }
}

extension BLELink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        servicesLeft = services.count
        if services.isEmpty { selectCharacteristics(on: peripheral) }
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        servicesLeft -= 1
        if servicesLeft == 0 { selectCharacteristics(on: peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            finishConnect(.failure(LinkError.bluetooth(error.localizedDescription)))
            return
        }
        let write = writeCharacteristic?.uuid.uuidString ?? "?"
        finishConnect(.success("Bluetooth : service \(characteristic.service?.uuid.uuidString ?? "?"), notify \(characteristic.uuid.uuidString), write \(write)"))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        buffer += String(decoding: data, as: UTF8.self)
        if buffer.contains(">") { resolve(.success(buffer)) }
    }
}
