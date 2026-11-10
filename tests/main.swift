import Foundation
import CoreBluetooth

// Standalone test script to verify profile matching, driver isolation, Step-Ladder engine,
// asymmetric hysteresis, dynamic dwell, velocity bypass, and Universal Condensation Safety Governor.
func runTests() {
    print("🚀 Starting Smart Cooler Control Test Suite (Tri-Mode & Step-Ladder Engine)...")

    // 1. Device Profile Matching Tests
    let testCases: [(name: String, expectedId: String?)] = [
        ("RM Magcooler 5pro", "rm-magcooler-5pro"),
        ("REDMAGIC Cooler 5 Pro", "rm-magcooler-5pro"),
        ("RM Magcooler 6pro", "rm-vccooler-6pro"),
        ("RM Magcooler 6pro+", "rm-vccooler-6proplus"),
        ("REDMAGIC Cooler 6 Pro+", "rm-vccooler-6proplus"),
        ("RM Magcooler 8pro", "rm-cryocooler-8pro"),
        ("REDMAGIC Cooler 8", "rm-cryocooler-8pro"),
        ("RM Magcooler 4pro", "rm-magcooler-4pro"),
        ("Black Shark MagCooler 5 Pro", "bs-magcooler-5pro"),
        ("BS 5Pro", "bs-magcooler-5pro"),
        ("Black Shark 4 Pro", "bs-magcooler-4pro"),
        ("Flydigi B8X", "fd-b8x"),
        ("feizhi b8x", "fd-b8x"),
        ("Flydigi B7X", "fd-b7x"),
        ("iQOO Cooler 2 Pro", "iqoo-clip-2pro"),
        ("iQOO Clip 2 Pro", "iqoo-clip-2pro"),
        ("OnePlus 45W Cooler", "op-liquid-45w"),
        ("OnePlus 27W Cooler", "op-freezing-27w"),
        ("MEMO CX08", "memo-cx08"),
        ("MEMO CX07", "memo-cx07"),
        ("Sony WH-1000XM4", nil),
        ("Apple Watch", nil)
    ]

    for (name, expectedId) in testCases {
        let matched = DeviceProfile.matching(deviceName: name)
        if let expected = expectedId {
            assert(matched != nil, "Expected match for '\(name)', got nil")
            assert(matched!.id == expected, "Expected '\(expected)' for '\(name)', got '\(matched!.id)'")
            print("  ✅ Match: '\(name)' -> \(matched!.brand) \(matched!.modelName) [\(matched!.id)]")
        } else {
            assert(matched == nil, "Expected no match for '\(name)', got '\(matched?.id ?? "")'")
            print("  ✅ Ignored: '\(name)' correctly identified as non-cooler")
        }
    }

    // 2. Black Shark Manufacturer Data Identification
    let bsMfgData = Data([0x8F, 0x03, 0x01, 0x02])
    let bsAdv = [CBAdvertisementDataManufacturerDataKey: bsMfgData]
    let bsMatched = DeviceProfile.matching(deviceName: "BR42-Cooler", advertisementData: bsAdv)
    assert(bsMatched != nil && bsMatched!.brand == "Black Shark", "Manufacturer data matching failed for Black Shark")
    print("  ✅ Manufacturer Data: Black Shark [0x8F, 0x03] -> \(bsMatched!.modelName)")

    // 3. Service UUID Identifications
    let fdServices = [CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")]
    let fdMatched = DeviceProfile.matching(deviceName: "Cooler-Unknown", advertisementData: [CBAdvertisementDataServiceUUIDsKey: fdServices])
    assert(fdMatched != nil && fdMatched!.brand == "Flydigi", "Service UUID matching failed for Flydigi")
    print("  ✅ Service UUID: Flydigi FFE0 -> \(fdMatched!.modelName)")

    let iqooServices = [CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")]
    let iqooMatched = DeviceProfile.matching(deviceName: "Cooler-Unknown", advertisementData: [CBAdvertisementDataServiceUUIDsKey: iqooServices])
    assert(iqooMatched != nil && iqooMatched!.id == "iqoo-clip-2pro", "Service UUID matching failed for iQOO")
    print("  ✅ Service UUID: iQOO FFF0 -> \(iqooMatched!.modelName)")

    let opServices = [CBUUID(string: "0000FEE7-0000-1000-8000-00805F9B34FB")]
    let opMatched = DeviceProfile.matching(deviceName: "OnePlus 45W Device", advertisementData: [CBAdvertisementDataServiceUUIDsKey: opServices])
    assert(opMatched != nil && opMatched!.id == "op-liquid-45w", "Service UUID matching failed for OnePlus 45W")
    print("  ✅ Service UUID: OnePlus FEE7 -> \(opMatched!.modelName)")

    // 4. Driver Instantiation and Isolation
    for profile in DeviceProfile.all {
        let driver = profile.makeDriver()
        assert(driver.profile.id == profile.id, "Driver profile mismatch for \(profile.id)")
        assert(driver.serviceUUID == profile.serviceUUID, "Driver serviceUUID mismatch for \(profile.id)")
        print("  ✅ Driver: \(profile.id) -> \(type(of: driver)) with Service \(driver.serviceUUID.uuidString)")
    }

    // 5. Deterministic Step-Ladder Thermal Engine Tests
    print("\n🧠 Testing Deterministic 4-Stage Step-Ladder Thermal Engine...")
    let engine = AutopilotPolicy()
    engine.resetStandby(isStandby: true)

    // A. Idle / Standby: Die at 45°C (< 50°C trigger) -> Standby (0% fan / .off)
    var dec = engine.evaluate(thermalState: .nominal, dieC: 45.0, now: 1000)
    assert(dec.tier.coolingTier == .standby && dec.tier.fanPercent == 0 && dec.tier.mode == .off,
           "Expected Standby at 45°C, got \(dec.tier.label)")
    print("  ✅ Step-Ladder Idle: 45°C (< 50°C) -> Standby (0% fan / OFF)")

    // B. Trigger Tier 1: Die reaches 50.0°C (>= 50°C) -> Immediate Step-Up to Tier 1 (40% fan / .low)
    dec = engine.evaluate(thermalState: .nominal, dieC: 50.0, now: 1001)
    assert(dec.tier.coolingTier == .tier1_low && dec.tier.fanPercent == 40 && dec.tier.mode == .low,
           "Expected Tier 1 at 50°C, got \(dec.tier.label)")
    print("  ✅ Step-Ladder Tier 1 Trigger: 50.0°C -> Immediate Step-Up to Tier 1 (40% fan / Low)")

    // C. Asymmetric Hysteresis Hold Tier 1: Die drops to 46°C (>= 42°C release threshold) -> STILL HOLDS Tier 1!
    // No chattering loop!
    dec = engine.evaluate(thermalState: .nominal, dieC: 46.0, now: 1002)
    assert(dec.tier.coolingTier == .tier1_low && dec.tier.fanPercent == 40,
           "Expected Tier 1 hold at 46°C (>= 42°C release), got \(dec.tier.label)")
    print("  ✅ Step-Ladder Tier 1 Asymmetric Hold: 46°C (>= 42°C release) -> Faithfully holds 40% fan")

    // D. Normal Step-Down Dwell Timing: Die gently cools from 42.1°C to 41.8°C (dT/dt = -0.3°C/s > -1.0°C/s)
    _ = engine.evaluate(thermalState: .nominal, dieC: 42.1, now: 1003)
    dec = engine.evaluate(thermalState: .nominal, dieC: 41.8, now: 1004) // rate = -0.3°C/s -> normal 20s dwell armed!
    assert(dec.tier.coolingTier == .tier1_low, "Expected Tier 1 to hold during dwell at t=1004")
    print("  ✅ Step-Ladder Step-Down Dwell Hold: 41.8°C at t=1004s -> Holds Tier 1 pending 20s dwell")

    // At t = 1018 (elapsed = 14s < 20s): STILL holds Tier 1!
    dec = engine.evaluate(thermalState: .nominal, dieC: 41.8, now: 1018)
    assert(dec.tier.coolingTier == .tier1_low, "Expected Tier 1 to hold at t=1018s (14s < 20s)")
    print("  ✅ Step-Ladder Dwell in-flight: 14s elapsed (< 20s) -> Fan stays smooth, no premature drop")

    // At t = 1025 (elapsed = 21s >= 20s): Dwell satisfied -> Transitions safely to Standby!
    dec = engine.evaluate(thermalState: .nominal, dieC: 41.8, now: 1025)
    assert(dec.tier.coolingTier == .standby && dec.tier.fanPercent == 0, "Expected Standby after 20s dwell")
    print("  ✅ Step-Ladder Dwell Complete: 21s elapsed (>= 20s) -> Smoothly steps down to Standby (0% fan)")

    // E. Immediate Multi-Tier Thermal Spike Jump:
    // Die suddenly spikes from Standby to 72.0°C (heavy workload compilation) -> JUMPS DIRECTLY TO TIER 4 TURBO!
    dec = engine.evaluate(thermalState: .nominal, dieC: 72.0, now: 1030)
    assert(dec.tier.coolingTier == .tier4_turbo && dec.tier.fanPercent == 100 && dec.tier.mode == .max,
           "Expected immediate jump to Tier 4 Turbo at 72°C, got \(dec.tier.label)")
    print("  ✅ Step-Ladder Spike Bypass: 41°C -> 72°C spike -> Instantly engages Tier 4 Turbo (100% fan / Max)")

    // F. Asymmetric Hold Tier 4: Die drops to 67.0°C (>= 66°C release threshold) -> MUST HOLD TIER 4 TURBO!
    dec = engine.evaluate(thermalState: .nominal, dieC: 67.0, now: 1035)
    assert(dec.tier.coolingTier == .tier4_turbo && dec.tier.fanPercent == 100,
           "Expected Tier 4 hold at 67°C (>= 66°C release), got \(dec.tier.label)")
    print("  ✅ Step-Ladder Tier 4 Asymmetric Hold: 67.0°C (>= 66°C release) -> Holds Tier 4 (100% fan)")

    // G. Step-Down from Tier 4 to Tier 3: Die drops to 63.0°C (< 66°C release, >= 61°C)
    // After 20s dwell, it settles into Tier 3 (80% fan / .medium)
    _ = engine.evaluate(thermalState: .nominal, dieC: 63.0, now: 1040)
    dec = engine.evaluate(thermalState: .nominal, dieC: 63.0, now: 1061)
    assert(dec.tier.coolingTier == .tier3_high && dec.tier.fanPercent == 80,
           "Expected Tier 3 (80% fan) at 63°C after dwell, got \(dec.tier.label)")
    print("  ✅ Step-Ladder Tier 4 -> Tier 3: 63.0°C (< 66°C) -> Settles into Tier 3 (80% fan)")

    // H. Step-Down from Tier 3 to Tier 2: Die drops to 57.0°C (< 61°C release, >= 55°C)
    _ = engine.evaluate(thermalState: .nominal, dieC: 57.0, now: 1070)
    dec = engine.evaluate(thermalState: .nominal, dieC: 57.0, now: 1091)
    assert(dec.tier.coolingTier == .tier2_med && dec.tier.fanPercent == 60,
           "Expected Tier 2 (60% fan) at 57°C after dwell, got \(dec.tier.label)")
    print("  ✅ Step-Ladder Tier 3 -> Tier 2: 57.0°C (< 61°C) -> Settles into Tier 2 (60% fan)")

    // I. Thermal Velocity Bypass (dT/dt <= -1.0°C/s):
    // Die rapidly plunges from 57°C to 45°C in 2 seconds (rate = -6.0°C/s)
    // Normal dwell of 20s is bypassed; fast dwell of 3s allows immediate step-down to prevent chassis overcooling!
    _ = engine.evaluate(thermalState: .nominal, dieC: 57.0, now: 1100)
    _ = engine.evaluate(thermalState: .nominal, dieC: 45.0, now: 1102) // Rapid drop detected!
    dec = engine.evaluate(thermalState: .nominal, dieC: 45.0, now: 1106) // 4s elapsed >= 3s fast dwell
    assert(dec.tier.coolingTier == .tier1_low && dec.tier.fanPercent == 40,
           "Expected fast dwell bypass down to Tier 1 at 45°C, got \(dec.tier.label)")
    print("  ✅ Thermal Velocity Bypass: Rapid cool (-6°C/s) -> Bypasses 20s dwell, steps down in 3s")

    // 6. Universal Condensation Safety Governor Tests (< 36°C Cutoff & >= 38°C Re-arm)
    print("\n🛡️ Testing Universal Condensation Safety Governor (< 36°C Cutoff & >= 38°C Re-Arm)...")

    // A. Sub-36°C Die Temperature forces Standby immediately across ALL modes
    let safetyPolicy = AutopilotPolicy()
    safetyPolicy.setTier(.tier4_turbo) // Pretend it was running at max
    let coldDec = safetyPolicy.evaluate(thermalState: .nominal, dieC: 35.5, now: 2000)
    assert(coldDec.tier.coolingTier == .standby && coldDec.tier.fanPercent == 0 && coldDec.tier.mode == .off,
           "Expected Safety Governor to force Standby at 35.5°C (< 36°C)")
    print("  ✅ Universal Cutoff: Die 35.5°C (< 36.0°C) -> Hard cutoff to Standby (0% fan / 0W)")

    // B. Re-Arm Deadband: Die warms to 37.0°C (< 38.0°C re-arm threshold) -> MUST REMAIN IN STANDBY
    let deadbandDec = safetyPolicy.evaluate(thermalState: .nominal, dieC: 37.0, now: 2001)
    assert(deadbandDec.tier.coolingTier == .standby && deadbandDec.tier.fanPercent == 0,
           "Expected Safety Governor to hold Standby at 37.0°C (< 38°C re-arm)")
    print("  ✅ Anti-Hunting Deadband: Die 37.0°C (< 38.0°C) -> Retains Standby, no relay chattering")

    // 7. Tri-Mode State & Manual Slider Progression Tests
    print("\n⚡ Testing Tri-Mode Representation & Manual Slider Progression...")
    assert(AppMode(persisted: "auto") == .auto)
    assert(AppMode(persisted: "manual") == .manual)
    assert(AppMode(persisted: "turbo") == .turbo)
    assert(AppMode(persisted: "off") == .manual) // Legacy fallback
    print("  ✅ AppMode Serialization: auto, manual, turbo, legacy 'off' roundtrip correctly")

    assert(Config.Safety.condensationCutoffC == 36.0, "Condensation cutoff must be 36.0°C")
    assert(Config.Safety.condensationRearmC == 38.0, "Condensation re-arm must be 38.0°C")
    print("  ✅ Safety Constants: 36.0°C Cutoff, 38.0°C Re-Arm confirmed (no arbitrary decay timeout)")

    // Slider progression verification: strictly increasing fan speed from Off to 100% Max
    let speeds = CoolingSliderView.steps.map(\.fanPercent)
    assert(speeds == [0, 40, 50, 60, 65, 75, 80, 85, 95, 100], "Slider fan speeds must be strictly progressive up to 100%")
    print("  ✅ Slider Progression: Off(0%) -> Low(40/50/60%) -> Med(65/75/80%) -> Max(85/95/100%) confirmed")

    // Fix verification: When 5 Pro reports mode 0x02 (.medium) at 100% fan, slider MUST match Step 9 (Max)!
    let maxMatch = CoolingSliderView.step(matching: .medium, fanPercent: 100)
    assert(maxMatch == 9, "Expected 100% fan to match Step 9 (Max), got \(maxMatch)")
    let medMatch = CoolingSliderView.step(matching: .medium, fanPercent: 80)
    assert(medMatch == 6, "Expected 80% fan to match Step 6 (Med), got \(medMatch)")
    print("  ✅ Med-to-Max Bug Seam Fixed: 100% fan correctly matches Step 9 (Max) without snapping back to Med")

    // 8. Mac Family Thermal LED Calibration
    print("\n🌈 Testing Mac Family-Aware LED Thermal Color Calibration...")
    let airCold = engine.heatColor(for: 41.0, macModel: "MacBook Air")
    assert(airCold.r == 0 && airCold.g == 255 && airCold.b == 0, "Expected pure green for MacBook Air at 41°C")
    print("  ✅ MacBook Air: 41°C (nominal) -> Pure Green LED (R: \(airCold.r), G: \(airCold.g), B: \(airCold.b))")

    let airWarm = engine.heatColor(for: 65.0, macModel: "MacBook Air")
    assert(airWarm.r > 150 && airWarm.g > 150, "Expected warm yellow for MacBook Air at 65°C")
    print("  ✅ MacBook Air: 65°C (moderate) -> Yellow/Amber LED (R: \(airWarm.r), G: \(airWarm.g), B: \(airWarm.b))")

    let airHot = engine.heatColor(for: 82.0, macModel: "MacBook Air")
    assert(airHot.r == 255 && airHot.g == 0, "Expected alert red for MacBook Air at 82°C")
    print("  ✅ MacBook Air: 82°C (hot/throttling) -> Pure Red LED (R: \(airHot.r), G: \(airHot.g), B: \(airHot.b))")

    let studioCold = engine.heatColor(for: 41.0, macModel: "Mac Studio")
    assert(studioCold.r == 0 && studioCold.g == 255, "Expected green for Mac Studio at 41°C")
    let studioHot = engine.heatColor(for: 74.0, macModel: "Mac Studio")
    assert(studioHot.r == 255 && studioHot.g == 0, "Expected red for Mac Studio at 74°C")
    print("  ✅ Mac Studio: 41°C -> Green, 74°C -> Pure Red LED")

    print("\n🎉 ALL TESTS PASSED! Deterministic Step-Ladder, Asymmetric Hysteresis, Dwell & Velocity Bypass, Universal Condensation Safety Governor & Multi-Brand Isolation verified.")
}

@main
struct TestRunner {
    static func main() {
        runTests()
    }
}
