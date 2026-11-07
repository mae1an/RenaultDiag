import XCTest
@testable import DiagCore

final class ParserTests: XCTestCase {
    func testSingleFrameWithSpacesAndPrompt() {
        XCTAssertEqual(ELMParser.parse("41 0C 1A F8 \r\r>"), .messages([[0x41, 0x0C, 0x1A, 0xF8]]))
    }

    func testSearchingIsIgnored() {
        XCTAssertEqual(ELMParser.parse("SEARCHING...\r410C1AF8\r\r>"), .messages([[0x41, 0x0C, 0x1A, 0xF8]]))
    }

    func testMultiFrameIsJoinedAndTrimmed() {
        let raw = "00A\r0:5902AF040192\r1:08246300080000\r\r>"
        XCTAssertEqual(ELMParser.parse(raw), .messages([[0x59, 0x02, 0xAF, 0x04, 0x01, 0x92, 0x08, 0x24, 0x63, 0x00]]))
    }

    func testTwoRespondersStaySeparate() {
        XCTAssertEqual(ELMParser.parse("410C1AF8\r410D32\r>"), .messages([[0x41, 0x0C, 0x1A, 0xF8], [0x41, 0x0D, 0x32]]))
    }

    func testNoDataAndFaults() {
        XCTAssertEqual(ELMParser.parse("NO DATA\r\r>"), .noData)
        XCTAssertEqual(ELMParser.parse("UNABLE TO CONNECT\r\r>"), .fault(.unableToConnect))
        XCTAssertEqual(ELMParser.parse("CAN ERROR\r\r>"), .fault(.canError))
        XCTAssertEqual(ELMParser.parse("?\r\r>"), .fault(.unknownCommand))
        XCTAssertEqual(ELMParser.parse("BUS INIT: ...ERROR\r\r>"), .fault(.busInitError))
    }

    func testBusInitOkIsNotAFault() {
        XCTAssertEqual(ELMParser.parse("BUS INIT: ...OK\r4100BE3FA813\r\r>"), .messages([[0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13]]))
    }
}

final class DecoderTests: XCTestCase {
    func testStandardCodes() {
        XCTAssertEqual(DTCDecoder.standardCode(high: 0x04, low: 0x01), "P0401")
        XCTAssertEqual(DTCDecoder.standardCode(high: 0x24, low: 0x63), "P2463")
        XCTAssertEqual(DTCDecoder.standardCode(high: 0xC0, low: 0x35), "U0035")
        XCTAssertEqual(DTCDecoder.standardCode(high: 0x90, low: 0x01), "B1001")
        XCTAssertEqual(DTCDecoder.standardCode(high: 0x41, low: 0x23), "C0123")
    }

    func testUDSEntriesAndPresence() {
        let dtcs = DTCDecoder.uds([0x59, 0x02, 0xAF, 0x04, 0x01, 0x92, 0x08, 0x24, 0x63, 0x00, 0x09])
        XCTAssertEqual(dtcs.map(\.code), ["P0401", "P2463"])
        XCTAssertEqual(dtcs[0].failureType, 0x92)
        XCTAssertEqual(dtcs[0].isPresent, false)
        XCTAssertEqual(dtcs[1].isPresent, true)
    }

    func testKWPThreeAndFourByteEntries() {
        XCTAssertEqual(DTCDecoder.kwp([0x57, 0x02, 0xC0, 0x35, 0x48, 0xD1, 0x40, 0x48]).map(\.code), ["U0035", "U1140"])
        let four = DTCDecoder.kwp([0x57, 0x01, 0x04, 0x01, 0x92, 0x48])
        XCTAssertEqual(four.first?.failureType, 0x92)
    }

    func testKWPEmpty() {
        XCTAssertEqual(DTCDecoder.kwp([0x57, 0x00]), [])
    }

    func testOBDModeThreeCANAndKLine() {
        XCTAssertEqual(DTCDecoder.obd([[0x43, 0x02, 0x04, 0x01, 0x24, 0x63]], isCAN: true).map(\.code), ["P0401", "P2463"])
        XCTAssertEqual(DTCDecoder.obd([[0x43, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00]], isCAN: false).map(\.code), ["P0401"])
    }

    func testPIDFormulas() {
        XCTAssertEqual(PIDCatalog.pid(0x0C)?.value(from: [0x1A, 0xF8]), 1726)
        XCTAssertEqual(PIDCatalog.pid(0x05)?.value(from: [0x7B]), 83)
        XCTAssertEqual(PIDCatalog.pid(0x42)?.value(from: [0x36, 0xB0]), 14)
    }

    func testExhaustSensorsReadFromSharedPID() throws {
        // 7A: support 03, differential 5,00 kPa, inlet 105,00 kPa, no outlet sensor.
        let reply: [UInt8] = [0x03, 0x01, 0xF4, 0x29, 0x04, 0x00, 0x00]
        XCTAssertEqual(try XCTUnwrap(PIDCatalog.pid(0x7A)?.value(from: reply)), 5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PIDCatalog.pid(0xC5)?.value(from: reply)), 105, accuracy: 0.001)
        XCTAssertNil(PIDCatalog.pid(0xC6)?.value(from: reply))
        XCTAssertEqual(PIDCatalog.pid(0xC5)?.request, 0x7A)

        // Negative differential, and too short a reply must not crash.
        XCTAssertEqual(try XCTUnwrap(PIDCatalog.pid(0x7A)?.value(from: [0x01, 0xFF, 0x9C])), -1, accuracy: 0.001)
        XCTAssertNil(PIDCatalog.pid(0x7A)?.value(from: [0x01]))

        // 78: sensor 1 at 300 °C.
        XCTAssertEqual(try XCTUnwrap(PIDCatalog.pid(0xC1)?.value(from: [0x01, 0x0D, 0x48])), 300, accuracy: 0.001)
    }

    func testPowerFromTorque() {
        let kW = PowerMath.kilowatts(torque: 340, rpm: 3750)
        XCTAssertEqual(kW, 133.5, accuracy: 0.1)
        XCTAssertEqual(PowerMath.horsepower(kilowatts: kW), 181.5, accuracy: 0.2)
    }

    func testPowerFromAcceleration() throws {
        // 2 m/s² from 60 km/h, read 8 times a second with whole km/h like real OBD.
        var estimator = AccelerationPowerEstimator(massKg: 1700)
        var power: Double?
        for step in 0...12 {
            let time = Double(step) / 8
            let speed = (60 / 3.6 + 2 * time) * 3.6
            power = estimator.add(speedKmh: speed.rounded(), at: time)
        }
        // Mean speed over the window about 18,5 m/s: inertia 63 kW, drag 3 kW, rolling 3,7 kW.
        XCTAssertEqual(try XCTUnwrap(power), 70, accuracy: 4)
    }

    func testNoPowerWhileCruising() {
        var estimator = AccelerationPowerEstimator(massKg: 1700)
        var power: Double?
        for step in 0...12 {
            power = estimator.add(speedKmh: 90, at: Double(step) / 8)
        }
        XCTAssertNil(power)
    }

    func testECUTableIsConsistent() {
        let uch = RenaultNetwork.allECUs.first { $0.address == "26" }
        XCTAssertEqual(uch?.tx, "745")
        XCTAssertEqual(uch?.rx, "765")
        XCTAssertEqual(RenaultNetwork.allECUs.first?.name, "Moteur (injection)")
        XCTAssertEqual(Set(RenaultNetwork.allECUs.map(\.address)).count, RenaultNetwork.allECUs.count)
    }
}

final class EndToEndTests: XCTestCase {
    private func connected(running: Bool = false, moving: Bool = false) async throws -> (ELMAdapter, SimulatedCar) {
        let car = SimulatedCar(running: running, moving: moving)
        let adapter = ELMAdapter(link: car)
        _ = try await adapter.initialize()
        return (adapter, car)
    }

    private func ecu(_ address: String) -> RenaultECU {
        RenaultNetwork.allECUs.first { $0.address == address }!
    }

    func testInitializeFindsCAN() async throws {
        let (adapter, _) = try await connected()
        let info = await adapter.info
        XCTAssertEqual(info?.isCAN, true)
        XCTAssertEqual(info?.voltage, "12.4V")
    }

    func testScanFindsOnlyPresentECUs() async throws {
        let (adapter, _) = try await connected()
        let box = ReportBox()
        try await RenaultDiagnostics(adapter: adapter).scan(RenaultNetwork.allECUs, progress: { _, _, _ in }, found: { box.add($0) })
        let reports = box.reports
        XCTAssertEqual(Set(reports.map(\.address)), ["7A", "01", "2C", "26", "51", "04"])
        XCTAssertEqual(reports.first { $0.address == "7A" }?.dtcs.map(\.code), ["P0401", "P2463", "P0100"])
        XCTAssertEqual(reports.first { $0.address == "01" }?.method, .kwp17)
        XCTAssertEqual(reports.first { $0.address == "51" }?.dtcs, [])
    }

    func testKLineProbeSkipsAbsentBusAndRestoresOBD() async throws {
        let (adapter, _) = try await connected(running: true)
        let diag = RenaultDiagnostics(adapter: adapter)
        let report = try await diag.read(RenaultNetwork.kLineECUs[0])
        XCTAssertNil(report)
        try await adapter.useOBDAddressing()
        let rpm = try await OBDService(adapter: adapter).read(PIDCatalog.pid(0x0C)!)
        XCTAssertNotNil(rpm)
    }

    func testClearKWPAndUDSUseTheRightFormat() async throws {
        let (adapter, _) = try await connected()
        let diag = RenaultDiagnostics(adapter: adapter)

        let abs = try await diag.clear(ecu("01"), method: .kwp17)
        XCTAssertTrue(abs.accepted)
        XCTAssertEqual(abs.remaining, [])

        // Wrong starting format must fall back to the other one.
        let uch = try await diag.clear(ecu("26"), method: .uds19)
        XCTAssertTrue(uch.accepted)

        let after = try await diag.read(ecu("01"))
        XCTAssertEqual(after?.dtcs, [])
    }

    func testClearReportsFaultThatComesBack() async throws {
        let (adapter, _) = try await connected()
        let outcome = try await RenaultDiagnostics(adapter: adapter).clear(ecu("2C"), method: .uds19)
        XCTAssertTrue(outcome.accepted)
        XCTAssertEqual(outcome.remaining.map(\.code), ["B1001"])
    }

    func testClearRefusedExplainsWhy() async throws {
        let (adapter, _) = try await connected(moving: true)
        let outcome = try await RenaultDiagnostics(adapter: adapter).clear(ecu("01"), method: .kwp17)
        XCTAssertFalse(outcome.accepted)
        XCTAssertTrue(outcome.message.contains("Conditions"))
    }

    func testOBDServices() async throws {
        let (adapter, _) = try await connected(running: true)
        let obd = OBDService(adapter: adapter)

        let supported = try await obd.supportedPIDs()
        XCTAssertTrue(supported.contains(0x0C))
        XCTAssertTrue(supported.contains(0x42))
        XCTAssertTrue(supported.contains(0x7A))
        XCTAssertTrue(supported.contains(0x78))

        let differential = try await obd.read(PIDCatalog.pid(0x7A)!)
        XCTAssertGreaterThan(differential ?? 0, 0)
        let outlet = try await obd.read(PIDCatalog.pid(0xC6)!)
        XCTAssertNil(outlet)
        let stuck = try await obd.read(PIDCatalog.pid(0xC2)!)
        XCTAssertEqual(stuck ?? -1, 0, accuracy: 0.001)

        let rpm = try await obd.read(PIDCatalog.pid(0x0C)!)
        XCTAssertGreaterThan(rpm ?? 0, 700)

        let stored = try await obd.dtcs(mode: 0x03)
        XCTAssertEqual(stored.map(\.code), ["P0401", "P2463", "P0100"])

        let vin = try await obd.vin()
        XCTAssertEqual(vin, "VF1JZ0G0000000001")

        let status = try await obd.status()
        XCTAssertEqual(status?.milOn, true)
        XCTAssertEqual(status?.isDiesel, true)

        let frame = try await obd.freezeFrame()
        XCTAssertEqual(frame?.cause, "P0401")
        XCTAssertFalse(frame?.values.isEmpty ?? true)
    }

    func testExplorerFindsValuesAndSeesWhichOnesMove() async throws {
        let (adapter, _) = try await connected(running: true)
        let explorer = ECUExplorer(adapter: adapter)
        let opened = try await explorer.open(ecu("7A"))
        XCTAssertTrue(opened)

        let requests: [[UInt8]] = [[0x22, 0x20, 0x00], [0x22, 0x20, 0x01], [0x22, 0x20, 0x02], [0x21, 0x03]]
        let box = ValueBox()
        try await explorer.search(requests, progress: { _, _ in }, found: { box.add($0) })
        XCTAssertEqual(box.values.map(\.id), ["222000", "222001"])

        var moving = box.values[1]
        var fixed = box.values[0]
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 20_000_000)
            moving.update(try await explorer.read(moving.request) ?? [])
            fixed.update(try await explorer.read(fixed.request) ?? [])
        }
        XCTAssertGreaterThan(moving.changingBytes, 0)
        XCTAssertEqual(fixed.changingBytes, 0)

        let speed = try await explorer.engineSpeed()
        XCTAssertGreaterThan(speed ?? 0, 700)

        try await explorer.close()
        let rpm = try await OBDService(adapter: adapter).read(PIDCatalog.pid(0x0C)!)
        XCTAssertNotNil(rpm)
    }

    func testExplorerOnlyEverSendsReadRequests() {
        XCTAssertTrue(ECUExplorer.standardRequests.allSatisfy(ECUExplorer.isReadOnly))
        for unsafe: [UInt8] in [[0x2E, 0x20, 0x00, 0x01], [0x14, 0xFF, 0xFF, 0xFF], [0x31, 0x01, 0x20], [0x27, 0x01], [0x22, 0x20, 0x00, 0x01]] {
            XCTAssertFalse(ECUExplorer.isReadOnly(unsafe))
        }
    }

    func testFuelTypeWinsOverTheIgnitionFlag() async throws {
        let (adapter, _) = try await connected(running: true)
        let status = try await OBDService(adapter: adapter).status()
        XCTAssertEqual(status?.fuelName, "Diesel")
    }

    func testOBDAddressingIsRestoredAfterDirectECUWork() async throws {
        let (adapter, _) = try await connected(running: true)
        _ = try await RenaultDiagnostics(adapter: adapter).clear(ecu("01"), method: .kwp17)
        let rpm = try await OBDService(adapter: adapter).read(PIDCatalog.pid(0x0C)!)
        XCTAssertNotNil(rpm)
    }

    func testEngineClearRefusedWhileRunning() async throws {
        let (adapter, car) = try await connected(running: true)
        let obd = OBDService(adapter: adapter)
        let refused = try await obd.clearEngine()
        XCTAssertEqual(refused, .negative(0x22))
        await car.setRunning(false)
        let accepted = try await obd.clearEngine()
        XCTAssertEqual(accepted, .positive([0x44]))
        let remaining = try await obd.dtcs(mode: 0x03)
        XCTAssertEqual(remaining, [])
    }
}

private final class ValueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ECUValue] = []
    var values: [ECUValue] { lock.withLock { stored } }
    func add(_ value: ECUValue) { lock.withLock { stored.append(value) } }
}

private final class ReportBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ECUReport] = []
    var reports: [ECUReport] { lock.withLock { stored } }
    func add(_ report: ECUReport) { lock.withLock { stored.append(report) } }
}
