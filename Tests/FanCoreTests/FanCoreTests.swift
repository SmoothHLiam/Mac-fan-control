import XCTest
@testable import FanCore

final class CodecTests: XCTestCase {
    func testFourCCRoundTrip() {
        XCTAssertEqual(SMCCodec.string(fromFourCC: SMCCodec.fourCC("F0Ac")), "F0Ac")
        XCTAssertEqual(SMCCodec.string(fromFourCC: SMCCodec.fourCC("ui8 ")), "ui8 ")
    }

    func testFloatRoundTrip() throws {
        let bytes = try XCTUnwrap(SMCCodec.encode(type: "flt ", value: 2310.5))
        XCTAssertEqual(SMCCodec.decode(type: "flt ", bytes: bytes), 2310.5)
        // 1.0f little-endian
        XCTAssertEqual(SMCCodec.decode(type: "flt ", bytes: [0x00, 0x00, 0x80, 0x3F]), 1.0)
    }

    func testFixedPointAndIntegers() {
        XCTAssertEqual(SMCCodec.decode(type: "sp78", bytes: [0x1E, 0x80]), 30.5)
        XCTAssertEqual(SMCCodec.decode(type: "fpe2", bytes: [0x0B, 0x54]), 725.0)
        XCTAssertEqual(SMCCodec.decode(type: "ui32", bytes: [0, 0, 1, 0]), 256)
        XCTAssertEqual(SMCCodec.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertNil(SMCCodec.decode(type: "zzzz", bytes: [1, 2, 3, 4]))
        XCTAssertNil(SMCCodec.decode(type: "flt ", bytes: [1, 2]))
    }

    func testEncodeRejectsOutOfRange() {
        XCTAssertNil(SMCCodec.encode(type: "ui8 ", value: 300))
        XCTAssertNil(SMCCodec.encode(type: "flt ", value: .nan))
        XCTAssertEqual(SMCCodec.encode(type: "ui8 ", value: 1), [1])
    }
}

final class CurveTests: XCTestCase {
    func testInterpolationAndClamping() {
        let c = FanCurve(points: [CurvePoint(temp: 40, percent: 0), CurvePoint(temp: 80, percent: 100)])
        XCTAssertEqual(c.percent(at: 20), 0)
        XCTAssertEqual(c.percent(at: 60), 50, accuracy: 0.001)
        XCTAssertEqual(c.percent(at: 120), 100)
    }

    func testNormalizeSortsAndKeepsMonotonic() {
        let c = FanCurve(points: [CurvePoint(temp: 80, percent: 40), CurvePoint(temp: 50, percent: 60),
                                  CurvePoint(temp: 90, percent: 200)])
        XCTAssertEqual(c.points.map(\.temp), [50, 80, 90])
        XCTAssertEqual(c.points.map(\.percent), [60, 60, 100])
    }

    func testEmptyCurveIsSafe() {
        XCTAssertEqual(FanCurve(points: []).percent(at: 70), 0)
    }
}

final class ControllerTests: XCTestCase {
    let limits = FanLimits(min: 1200, max: 6000)
    func temps(cpu: Double) -> TemperatureSnapshot {
        TemperatureSnapshot(values: ["Tp01": cpu], categories: ["Tp01": .cpu])
    }

    func testAutoReleases() {
        var c = FanController()
        XCTAssertEqual(c.decide(fan: 0, setting: .auto, limits: limits, temps: temps(cpu: 50), actualRPM: 1300, dt: 1), .automatic)
    }

    func testManualRampsUpThenHolds() {
        var c = FanController()
        let s = FanSetting(mode: .manual, manualPercent: 100)
        let first = c.decide(fan: 0, setting: s, limits: limits, temps: temps(cpu: 50), actualRPM: 1200, dt: 1)
        XCTAssertEqual(first, .target(rpm: 3000))   // 1200 + 1800 rpm/s
        let second = c.decide(fan: 0, setting: s, limits: limits, temps: temps(cpu: 50), actualRPM: 3000, dt: 1)
        XCTAssertEqual(second, .target(rpm: 4800))
        _ = c.decide(fan: 0, setting: s, limits: limits, temps: temps(cpu: 50), actualRPM: 4800, dt: 1)
        XCTAssertEqual(c.decide(fan: 0, setting: s, limits: limits, temps: temps(cpu: 50), actualRPM: 6000, dt: 1), .target(rpm: 6000))
    }

    func testRampDownIsSlower() {
        var c = FanController()
        _ = c.decide(fan: 0, setting: FanSetting(mode: .max), limits: limits, temps: temps(cpu: 50), actualRPM: 6000, dt: 1)
        let down = c.decide(fan: 0, setting: FanSetting(mode: .manual, manualPercent: 0), limits: limits, temps: temps(cpu: 50), actualRPM: 6000, dt: 1)
        XCTAssertEqual(down, .target(rpm: 5600))
    }

    func testDeadbandSuppressesSmallChanges() {
        var c = FanController()
        _ = c.decide(fan: 0, setting: FanSetting(mode: .manual, manualPercent: 50), limits: limits, temps: temps(cpu: 50), actualRPM: 3600, dt: 1)
        let near = c.decide(fan: 0, setting: FanSetting(mode: .manual, manualPercent: 50.5), limits: limits, temps: temps(cpu: 50), actualRPM: 3600, dt: 1)
        XCTAssertEqual(near, .target(rpm: 3600))
    }

    func testCurveFollowsTemperature() {
        var c = FanController()
        c.config.tempSmoothing = 1
        let s = FanSetting(mode: .curve, curve: FanCurve(points: [CurvePoint(temp: 40, percent: 0), CurvePoint(temp: 80, percent: 100)]), sensor: .cpu)
        // 60°C -> 50% -> 3600 rpm; start at actual 3600 so no ramp.
        XCTAssertEqual(c.decide(fan: 0, setting: s, limits: limits, temps: temps(cpu: 60), actualRPM: 3600, dt: 1), .target(rpm: 3600))
    }

    func testCurveWithoutTemperatureFailsSafeToMax() {
        var c = FanController()
        let s = FanSetting(mode: .curve)
        let d = c.decide(fan: 0, setting: s, limits: limits, temps: TemperatureSnapshot(), actualRPM: 6000, dt: 1)
        XCTAssertEqual(d, .target(rpm: 6000))
    }

    func testCriticalLatchForcesMaxImmediatelyAndReleasesWithHysteresis() {
        var c = FanController()
        let s = FanSetting(mode: .manual, manualPercent: 0)
        c.updateSafety(siliconTemp: 96)
        XCTAssertTrue(c.criticalLatched)
        XCTAssertEqual(c.decide(fan: 0, setting: s, limits: limits, temps: temps(cpu: 96), actualRPM: 1200, dt: 0.1), .target(rpm: 6000))
        c.updateSafety(siliconTemp: 92)          // still within hysteresis band
        XCTAssertTrue(c.criticalLatched)
        c.updateSafety(siliconTemp: 87)
        XCTAssertFalse(c.criticalLatched)
    }

    func testCriticalDoesNotOverrideAuto() {
        var c = FanController()
        c.updateSafety(siliconTemp: 99)
        XCTAssertEqual(c.decide(fan: 0, setting: .auto, limits: limits, temps: temps(cpu: 99), actualRPM: 3000, dt: 1), .automatic)
    }
}

final class SensorTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(SensorCatalog.classify(key: "Tp01").category, .cpu)
        XCTAssertEqual(SensorCatalog.classify(key: "Tg0D").category, .gpu)
        XCTAssertEqual(SensorCatalog.classify(key: "TB0T").category, .battery)
        XCTAssertEqual(SensorCatalog.classify(key: "Tx9z").category, .other)
    }

    func testSnapshotAggregates() {
        let s = TemperatureSnapshot(values: ["Tp01": 50, "Tp02": 70, "Tg01": 60, "TB0T": 99],
                                    categories: ["Tp01": .cpu, "Tp02": .cpu, "Tg01": .gpu, "TB0T": .battery])
        XCTAssertEqual(s.peak(.cpu), 70)
        XCTAssertEqual(s.average(.cpu), 60)
        XCTAssertEqual(s.silicon, 70)          // battery ignored
        XCTAssertEqual(s.hottest, 99)
        XCTAssertEqual(s.value(for: .key("Tg01")), 60)
    }
}

final class ProfileTests: XCTestCase {
    func testCodableRoundTrip() throws {
        var p = Profile(name: "Mine", fallback: FanSetting(mode: .curve, curve: .quiet, sensor: .key("Tp01")))
        p.set(FanSetting(mode: .manual, manualPercent: 33), forFan: 1)
        let data = try JSONEncoder().encode(AppConfig.with(p))
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.working, p)
        XCTAssertEqual(decoded.working.setting(forFan: 1).manualPercent, 33)
        XCTAssertEqual(decoded.working.setting(forFan: 0).sensor, .key("Tp01"))
    }

    func testBuiltInIDsAreStable() {
        XCTAssertEqual(Profile.builtIns.count, 5)
        XCTAssertEqual(Set(Profile.builtIns.map(\.id)).count, 5)
    }
}

private extension AppConfig {
    static func with(_ p: Profile) -> AppConfig {
        var c = AppConfig()
        c.working = p
        return c
    }
}
