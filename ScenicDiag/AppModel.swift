import DiagCore
import Foundation
import Observation
import UIKit

struct Sample: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

struct ConsoleLine: Identifiable {
    let id = UUID()
    let sent: String
    let received: String
}

/// Snapshot saved before every clear, so a fault list is never lost.
struct HistoryEntry: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var title: String
    var reports: [ECUReport]
}

@MainActor
@Observable
final class AppModel {
    enum Connection: Equatable {
        case disconnected
        case connecting(String)
        case connected(AdapterInfo)
    }

    private enum JobKind { case live, diagnostic }

    // Connection
    private(set) var connection: Connection = .disconnected
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var bluetoothMessage: String?
    private(set) var isDemo = false
    var errorMessage: String?

    // Live data
    private(set) var supportedPIDs: Set<UInt8> = []
    private(set) var values: [UInt8: Double] = [:]
    private(set) var history: [UInt8: [Sample]] = [:]
    private(set) var requestsPerSecond = 0.0
    private(set) var isRecording = false
    private(set) var recordedCSV: URL?
    var selectedPIDs: [UInt8] = AppModel.loadSelection() {
        didSet { UserDefaults.standard.set(selectedPIDs.map(Int.init), forKey: "selectedPIDs") }
    }

    // Faults
    private(set) var reports: [ECUReport] = []
    private(set) var hasScanned = false
    private(set) var scanProgress: (done: Int, total: Int, name: String)?
    private(set) var isClearing = false
    private(set) var outcomes: [String: ClearOutcome] = [:]
    private(set) var savedHistory: [HistoryEntry] = []
    var demoEngineRunning = true

    // Vehicle
    private(set) var vin: String?
    private(set) var status: VehicleStatus?
    private(set) var freezeFrame: FreezeFrame?
    private(set) var pendingDTCs: [DTC] = []
    private(set) var permanentDTCs: [DTC] = []
    private(set) var voltage: String?
    private(set) var isLoadingVehicle = false

    // Discovery
    private(set) var explorerValues: [ECUValue] = []
    private(set) var explorerProgress: (done: Int, total: Int)?
    private(set) var isWatching = false
    private(set) var explorerRounds = 0
    private var explorerLog: [String] = []

    // Console
    private(set) var console: [ConsoleLine] = []
    private(set) var isConsoleBusy = false

    private var adapter: ELMAdapter?
    private var demoCar: SimulatedCar?
    private var ble: BLELink?
    private var job: Task<Void, Never>?
    private var jobKind: JobKind?
    private var recording: [(Date, UInt8, Double)] = []

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    var adapterInfo: AdapterInfo? {
        if case .connected(let info) = connection { return info }
        return nil
    }

    var isBusy: Bool { scanProgress != nil || isClearing || isLoadingVehicle || explorerProgress != nil || isWatching }

    init() {
        savedHistory = Self.loadHistory()
    }

    // MARK: Connection

    func startBluetooth() {
        guard ble == nil else { ble?.startScan(); return }
        let link = BLELink()
        link.onStateChange = { [weak self] message in self?.bluetoothMessage = message }
        link.onDevice = { [weak self] device in self?.add(device) }
        link.onDisconnect = { [weak self] in self?.handleDisconnect() }
        ble = link
    }

    private func add(_ device: DiscoveredDevice) {
        devices.removeAll { $0.id == device.id }
        devices.append(device)
        devices.sort { ($0.isLikelyAdapter ? 0 : 1, -$0.rssi) < ($1.isLikelyAdapter ? 0 : 1, -$1.rssi) }
    }

    func connect(to device: DiscoveredDevice) {
        guard let ble else { return }
        connection = .connecting(device.name)
        isDemo = false
        Task {
            do {
                let description = try await ble.connect(to: device.id)
                log(sent: "BLE", received: description)
                try await finishConnection(link: ble)
            } catch {
                ble.disconnect()
                connection = .disconnected
                errorMessage = error.localizedDescription
                ble.startScan()
            }
        }
    }

    func connectDemo() {
        connection = .connecting("voiture de démo")
        isDemo = true
        demoEngineRunning = true
        let car = SimulatedCar(latencyMs: 25, running: true)
        demoCar = car
        Task {
            do {
                try await finishConnection(link: car)
            } catch {
                connection = .disconnected
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finishConnection(link: ELMLink) async throws {
        let adapter = ELMAdapter(link: link)
        await adapter.setLogger { [weak self] sent, received in
            Task { @MainActor in self?.log(sent: sent, received: received) }
        }
        self.adapter = adapter
        let info = try await adapter.initialize()
        supportedPIDs = try await OBDService(adapter: adapter).supportedPIDs()
        connection = .connected(info)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func disconnect() {
        job?.cancel()
        ble?.disconnect()
        handleDisconnect()
        if !isDemo { ble?.startScan() }
    }

    private func handleDisconnect() {
        job?.cancel()
        adapter = nil
        demoCar = nil
        connection = .disconnected
        isDemo = false
        values = [:]
        history = [:]
        scanProgress = nil
        isClearing = false
        isLoadingVehicle = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Jobs

    /// Only one job can use the adapter, because the CAN headers are shared state.
    private func run(_ kind: JobKind, _ work: @escaping @MainActor () async throws -> Void) {
        let previous = job
        previous?.cancel()
        jobKind = kind
        job = Task {
            await previous?.value
            do {
                try await work()
            } catch is CancellationError {
            } catch LinkError.disconnected {
                handleDisconnect()
                errorMessage = LinkError.disconnected.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            if jobKind == kind { jobKind = nil }
        }
    }

    // MARK: Live

    func startLive() {
        guard let adapter, !isBusy, jobKind != .live else { return }
        run(.live) { [weak self] in
            try await adapter.useOBDAddressing()
            let obd = OBDService(adapter: adapter)
            var count = 0
            var windowStart = Date()
            while !Task.isCancelled {
                guard let self else { return }
                let pids = self.selectedPIDs.compactMap(PIDCatalog.pid).filter { self.supportedPIDs.contains($0.request) }
                if pids.isEmpty {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }
                for pid in pids {
                    try Task.checkCancellation()
                    if let value = try await obd.read(pid) { self.store(value, for: pid.id) }
                    count += 1
                }
                let elapsed = Date().timeIntervalSince(windowStart)
                if elapsed >= 1 {
                    self.requestsPerSecond = Double(count) / elapsed
                    count = 0
                    windowStart = Date()
                }
            }
        }
    }

    func stopLive() {
        if jobKind == .live { job?.cancel() }
    }

    private func store(_ value: Double, for id: UInt8) {
        let now = Date()
        values[id] = value
        var samples = history[id, default: []]
        samples.append(Sample(time: now, value: value))
        if samples.count > 240 { samples.removeFirst(samples.count - 240) }
        history[id] = samples
        if isRecording { recording.append((now, id, value)) }
    }

    /// For exhaust sensors: says so when the value has not moved over the last 20 readings.
    func stuckLabel(for pid: PID) -> String? {
        guard pid.group == .exhaust, let samples = history[pid.id]?.suffix(20), samples.count == 20,
              let low = samples.map(\.value).min(), let high = samples.map(\.value).max(),
              high - low < 0.01 else { return nil }
        return abs(high) < 0.01 ? "Reste à 0" : "Valeur figée"
    }

    func toggleRecording() {
        if isRecording {
            isRecording = false
            recordedCSV = writeCSV()
        } else {
            recording = []
            recordedCSV = nil
            isRecording = true
        }
    }

    private func writeCSV() -> URL? {
        var text = "heure;mesure;valeur;unité\n"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (date, id, value) in recording {
            guard let pid = PIDCatalog.pid(id) else { continue }
            text += "\(formatter.string(from: date));\(pid.name);\(String(format: "%.3f", value));\(pid.unit)\n"
        }
        return write(text, name: "RenaultDiag-enregistrement.csv")
    }

    func togglePID(_ id: UInt8) {
        if let index = selectedPIDs.firstIndex(of: id) {
            selectedPIDs.remove(at: index)
        } else {
            selectedPIDs.append(id)
        }
    }

    // MARK: Faults

    func scan(ecus: [RenaultECU]) {
        guard let adapter else { return }
        reports = []
        outcomes = [:]
        hasScanned = false
        scanProgress = (0, ecus.count, ecus.first?.name ?? "")
        run(.diagnostic) { [weak self] in
            defer { self?.scanProgress = nil }
            try await RenaultDiagnostics(adapter: adapter).scan(ecus) { done, total, ecu in
                Task { @MainActor in self?.scanProgress = (done, total, ecu.name) }
            } found: { report in
                Task { @MainActor in self?.reports.append(report) }
            }
            self?.hasScanned = true
        }
    }

    func cancelScan() {
        job?.cancel()
    }

    func ecu(for report: ECUReport) -> RenaultECU? {
        (report.isKLine ? RenaultNetwork.kLineECUs : RenaultNetwork.allECUs).first { $0.address == report.address }
    }

    /// Reasons the car should not have its fault memory cleared right now.
    private func clearBlocker(using obd: OBDService) async throws -> String? {
        let adapterInUse = adapter
        try await adapterInUse?.useOBDAddressing()
        if let speed = try await obd.read(PIDCatalog.pid(0x0D)!), speed > 0 {
            return "La voiture roule. Arrête-toi pour effacer les défauts."
        }
        if let rpm = try await obd.read(PIDCatalog.pid(0x0C)!), rpm > 50 {
            return "Le moteur tourne. Coupe le moteur et laisse le contact mis, puis recommence."
        }
        return nil
    }

    func clear(_ targets: [ECUReport]) {
        guard let adapter, !targets.isEmpty else { return }
        isClearing = true
        run(.diagnostic) { [weak self] in
            defer { self?.isClearing = false }
            guard let self else { return }
            let obd = OBDService(adapter: adapter)
            if let demoCar = self.demoCar { await demoCar.setRunning(self.demoEngineRunning) }
            if let blocker = try await self.clearBlocker(using: obd) {
                self.errorMessage = blocker
                return
            }
            self.saveHistory(title: targets.count == 1 ? targets[0].name : "Tous les calculateurs")
            let diag = RenaultDiagnostics(adapter: adapter)
            for report in targets {
                try Task.checkCancellation()
                guard let ecu = self.ecu(for: report) else { continue }
                let outcome = try await diag.clear(ecu, method: report.method)
                if ecu.address == "7A" {
                    // The legislated OBD memory is separate from the Renault one.
                    _ = try await obd.clearEngine()
                }
                self.outcomes[report.id] = outcome
                if let index = self.reports.firstIndex(where: { $0.id == report.id }), outcome.accepted {
                    self.reports[index].dtcs = outcome.remaining
                }
            }
        }
    }

    var totalFaults: Int { reports.reduce(0) { $0 + $1.dtcs.count } }

    func reportText() -> String {
        var lines = ["Rapport RenaultDiag, \(Date().formatted(date: .abbreviated, time: .shortened))"]
        if let vin { lines.append("VIN : \(vin)") }
        if let info = adapterInfo { lines.append("Protocole : \(info.protocolName)") }
        for report in reports {
            lines.append("")
            lines.append("\(report.name) [\(report.address)]" + (report.identification.map { " : \($0)" } ?? ""))
            if let error = report.readError { lines.append("  Lecture impossible : \(error)") }
            if report.dtcs.isEmpty && report.readError == nil { lines.append("  Aucun défaut") }
            for dtc in report.dtcs {
                let failure = dtc.failureDescription.map { ", \($0)" } ?? ""
                lines.append("  \(dtc.code) (\(dtc.raw)) : \(dtc.description)\(failure)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func saveHistory(title: String) {
        guard !reports.isEmpty else { return }
        savedHistory.insert(HistoryEntry(date: Date(), title: title, reports: reports), at: 0)
        if let data = try? JSONEncoder().encode(savedHistory) {
            try? data.write(to: Self.historyURL)
        }
    }

    private static var historyURL: URL {
        URL.documentsDirectory.appending(path: "historique.json")
    }

    private static func loadHistory() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    // MARK: Vehicle

    func loadVehicle() {
        guard let adapter else { return }
        isLoadingVehicle = true
        run(.diagnostic) { [weak self] in
            defer { self?.isLoadingVehicle = false }
            try await adapter.useOBDAddressing()
            let obd = OBDService(adapter: adapter)
            let voltage = try await adapter.batteryVoltage()
            let vin = try await obd.vin()
            let status = try await obd.status()
            let frame = try await obd.freezeFrame()
            let pending = try await obd.dtcs(mode: 0x07)
            let permanent = try await obd.dtcs(mode: 0x0A)
            self?.voltage = voltage
            self?.vin = vin
            self?.status = status
            self?.freezeFrame = frame
            self?.pendingDTCs = pending
            self?.permanentDTCs = permanent
        }
    }

    // MARK: Discovery

    private var engineECU: RenaultECU? { RenaultNetwork.allECUs.first { $0.address == "7A" } }

    /// Refuses to run while the car moves: nobody should be watching this while driving.
    private func refuseIfMoving(_ adapter: ELMAdapter) async throws -> Bool {
        try await adapter.useOBDAddressing()
        if let speed = try await OBDService(adapter: adapter).read(PIDCatalog.pid(0x0D)!), speed > 0 {
            errorMessage = "Arrête-toi avant de lancer cette recherche."
            return true
        }
        return false
    }

    func startExplorerSearch() {
        guard let adapter, let engineECU else { return }
        explorerValues = []
        explorerLog = []
        explorerRounds = 0
        explorerProgress = (0, ECUExplorer.standardRequests.count)
        run(.diagnostic) { [weak self] in
            defer { self?.explorerProgress = nil }
            guard let self, try await !self.refuseIfMoving(adapter) else { return }
            let explorer = ECUExplorer(adapter: adapter)
            guard try await explorer.open(engineECU) else {
                self.errorMessage = "Le calculateur moteur ne répond pas. Le contact est-il mis ?"
                return
            }
            do {
                try await explorer.search(ECUExplorer.standardRequests) { done, total in
                    Task { @MainActor in self.explorerProgress = (done, total) }
                } found: { value in
                    Task { @MainActor in self.explorerValues.append(value) }
                }
            } catch is CancellationError {}
            try await explorer.close()
        }
    }

    /// Re-reads everything found, in a loop, to see which values follow the engine.
    func startExplorerWatch() {
        guard let adapter, let engineECU, !explorerValues.isEmpty else { return }
        isWatching = true
        run(.diagnostic) { [weak self] in
            defer { self?.isWatching = false }
            guard let self, try await !self.refuseIfMoving(adapter) else { return }
            let explorer = ECUExplorer(adapter: adapter)
            guard try await explorer.open(engineECU) else { return }
            do {
                while !Task.isCancelled {
                    try await explorer.keepAlive()
                    let time = Date().timeIntervalSince1970
                    if let rpm = try await explorer.engineSpeed() {
                        self.explorerLog.append(String(format: "%.2f;010C;%.0f", time, rpm))
                    }
                    for index in self.explorerValues.indices {
                        try Task.checkCancellation()
                        guard let reply = try await explorer.read(self.explorerValues[index].request) else { continue }
                        self.explorerValues[index].update(reply)
                        self.explorerLog.append(String(format: "%.2f;%@;%@", time, self.explorerValues[index].id, hexString(reply)))
                    }
                    if self.explorerLog.count > 50_000 { self.explorerLog.removeFirst(10_000) }
                    self.explorerRounds += 1
                }
            } catch is CancellationError {}
            try await explorer.close()
        }
    }

    func stopExplorer() {
        job?.cancel()
    }

    func explorerFile() -> URL? {
        var text = "demande;dernière réponse;minimum;maximum;octets qui bougent\n"
        for value in explorerValues {
            text += "\(value.id);\(hexString(value.latest));\(hexString(value.low));\(hexString(value.high));\(value.changingBytes)\n"
        }
        text += "\nheure;demande;réponse\n" + explorerLog.joined(separator: "\n")
        return write(text, name: "RenaultDiag-decouverte.txt")
    }

    // MARK: Console

    func sendRaw(_ text: String) {
        guard let adapter else { return }
        let command = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !command.isEmpty else { return }
        isConsoleBusy = true
        run(.diagnostic) { [weak self] in
            defer { self?.isConsoleBusy = false }
            try await adapter.at(command, timeout: 5)
        }
    }

    private func log(sent: String, received: String) {
        let text = received
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespaces)
        console.append(ConsoleLine(sent: sent, received: text))
        if console.count > 2000 { console.removeFirst(console.count - 2000) }
    }

    func consoleFile() -> URL? {
        let text = console.map { "> \($0.sent)\n\($0.received)" }.joined(separator: "\n")
        return write(text, name: "RenaultDiag-journal.txt")
    }

    func reportFile() -> URL? {
        write(reportText(), name: "RenaultDiag-rapport.txt")
    }

    private func write(_ text: String, name: String) -> URL? {
        let url = URL.temporaryDirectory.appending(path: name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private static func loadSelection() -> [UInt8] {
        if let saved = UserDefaults.standard.array(forKey: "selectedPIDs") as? [Int], !saved.isEmpty {
            return saved.map { UInt8($0) }
        }
        return [0x0C, 0x0D, 0x05, 0x04, 0x0B, 0x42]
    }
}
