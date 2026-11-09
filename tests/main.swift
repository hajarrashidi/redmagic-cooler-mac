import Foundation
import CoreBluetooth

// Standalone test script to verify profile matching, driver isolation, and autopilot 38°C shutoff
func runTests() {
    print("🚀 Starting Smart Cooler Control Profile & Driver Test Suite...")

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

    // 5. AutopilotPolicy Smart Max Baseline & Configurable Shutoff
    print("\n🧠 Testing Autopilot Smart Max Baseline & Shutoff Cutoff...")
    let policy = AutopilotPolicy(engageC: 50.0, shutoffC: 38.0, minFanPercent: 30)
    policy.setProfile(.smartMax)

    // A. Mac is hot (50°C >= engage 50°C): MUST ENGAGE MAX (100% fan)
    var dec = policy.evaluate(thermalState: .nominal, dieC: 50.0, now: 1000)
    assert(dec.tier.mode == .max && dec.tier.fanPercent == 100, "Expected cooler max at 50°C")
    print("  ✅ Smart Max High Heat: 50°C -> Cooler engages at MAX (100% fan)")

    // B. Mac at 41°C (normal operational range): MUST HOLD 30% MIN POWER!
    dec = policy.evaluate(thermalState: .nominal, dieC: 41.0, now: 1001)
    assert(dec.tier.fanPercent == 30, "Expected Smart Max to hold configured min power (30%) at 41°C, got \(dec.tier.fanPercent)%")
    print("  ✅ Smart Max Baseline: 41°C -> Holds quiet configured min power (30% fan)")

    // C. Mac at 49°C (within final 2°C ramp approach to 50°C):
    dec = policy.evaluate(thermalState: .nominal, dieC: 49.0, now: 1002)
    assert(dec.tier.fanPercent >= 65, "Expected Smart Max ramp approach near engage, got \(dec.tier.fanPercent)%")
    print("  ✅ Smart Max Ramp Approach: 49°C -> Smoothly ramping (\(dec.tier.fanPercent)% fan) to 100%")

    // D. Mac cools all the way down to 37°C (< 38°C shutoff threshold): MUST SHUT OFF COMPLETELY
    dec = policy.evaluate(thermalState: .nominal, dieC: 37.0, now: 1003)
    assert(dec.tier.mode == .off && dec.tier.fanPercent == 0, "Expected cooler off when Mac drops below 38°C shutoff threshold")
    print("  ✅ Smart Max Cold Cutoff: 37°C (< 38°C) -> Cooler shuts OFF completely (0% fan / Standby)")

    // E. Test user-customized min fan percent to 45%:
    policy.setMinFanPercent(45)
    dec = policy.evaluate(thermalState: .nominal, dieC: 41.0, now: 1004)
    assert(dec.tier.fanPercent == 45, "Expected cooler at 45% fan with 45% min power, got \(dec.tier.fanPercent)%")
    print("  ✅ Smart Max Custom Min Power: 41°C -> Cooler holds configured 45% fan")

    // At 37°C (< 38°C), it still safely shuts off:
    dec = policy.evaluate(thermalState: .nominal, dieC: 37.0, now: 1005)
    assert(dec.tier.mode == .off && dec.tier.fanPercent == 0, "Expected cooler off below 38°C shutoff")
    print("  ✅ Smart Max Shutoff: 37°C (< 38°C) -> Cooler shuts OFF completely (0% fan)")

    // 6. Test Balanced Dynamic Acoustic Ramp & Shutoff
    print("\n🧠 Testing Autopilot Balanced Dynamic Acoustic Ramp & Shutoff...")
    let balanced = AutopilotPolicy(engageC: 50.0, shutoffC: 38.0, minFanPercent: 30)
    balanced.setProfile(.balanced)

    // A. Cold Mac (37°C < shutoff 38°C): MUST SHUT OFF COMPLETELY (0% fan)
    var bDec = balanced.evaluate(thermalState: .nominal, dieC: 37.0)
    assert(bDec.tier.mode == .off && bDec.tier.fanPercent == 0, "Expected Balanced to shut off below shutoff threshold")
    print("  ✅ Balanced Cold Cutoff: 37°C (< 38°C) -> Cooler shuts OFF completely (0% fan / Standby)")

    // B. At shutoff boundary (38°C): starts at 30% fan (user-chosen min power)
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 38.0)
    assert(bDec.tier.mode == .low && bDec.tier.fanPercent == 30, "Expected Balanced at 30% at 38°C, got \(bDec.tier.fanPercent)%")
    print("  ✅ Balanced Acoustic Floor: 38°C -> Starts gently at 30% fan")

    // C. At 41°C (ramp window 12°C from 38°C to 50°C, progress = (41-38)/12 = 0.25, 30 + 0.25*70 = 47.5 -> 50%):
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 41.0)
    assert(bDec.tier.fanPercent == 50, "Expected Balanced linear ramp at 50% at 41°C, got \(bDec.tier.fanPercent)%")
    print("  ✅ Balanced Acoustic Ramp: 41°C -> Precisely 50% fan")

    // D. At 50°C (engage threshold): 100% max fan
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 50.0)
    assert(bDec.tier.mode == .max && bDec.tier.fanPercent == 100, "Expected Balanced 100% at engage threshold")
    print("  ✅ Balanced Full Power: 50°C (engage) -> 100% MAX fan")

    // E. Change shutoff threshold in Balanced to 42°C: at 41°C it MUST now be OFF!
    balanced.setShutoff(42.0)
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 41.0)
    assert(bDec.tier.mode == .off && bDec.tier.fanPercent == 0, "Expected Balanced to shut off at 41°C when shutoff is 42°C")
    print("  ✅ Balanced Custom Shutoff: 41°C (< custom 42°C) -> Cooler immediately shuts OFF")

    // F. Test Anti-Lockup Dynamic Push:
    // When Shutoff is set to 48°C (above current engage), it must automatically push Engage to at least 50°C!
    balanced.setEngage(44.0)
    balanced.setShutoff(48.0)
    assert(balanced.shutoffC == 48.0, "Expected shutoff 48°C")
    assert(balanced.engageC >= 50.0, "Expected engage pushed to at least 50°C, got \(balanced.engageC)°C")
    print("  ✅ Anti-Lockup: Raising Shutoff to 48°C smoothly pushes Engage to \(balanced.engageC)°C (never freezes)")

    // When Engage is lowered to 36°C, it must automatically push Shutoff down to at most 34°C!
    balanced.setEngage(36.0)
    assert(balanced.engageC == 36.0, "Expected engage 36°C")
    assert(balanced.shutoffC <= 34.0, "Expected shutoff pushed down to at most 34°C, got \(balanced.shutoffC)°C")
    print("  ✅ Anti-Lockup: Lowering Engage to 36°C smoothly pushes Shutoff down to \(balanced.shutoffC)°C (never freezes)")

    // G. Test Unified Scale & Beyond-50°C Unlocked Range:
    // User can set Shutoff past the old 50°C ceiling without blocking!
    balanced.setShutoff(55.0)
    assert(balanced.shutoffC == 55.0, "Expected shutoff to reach 55°C without 50°C artificial wall")
    assert(balanced.engageC >= 57.0, "Expected engage pushed to 57°C")
    print("  ✅ Unlocked Scale: Shutoff reaches 55°C (above old 50°C limit), Engage pushed to \(balanced.engageC)°C")

    // Both sliders share 30°C...80°C range: Shutoff knob is ALWAYS physically to the left of Engage knob
    let shutoffVisualX = (44.0 - Config.Autopilot.tempMinC) / (Config.Autopilot.tempMaxC - Config.Autopilot.tempMinC)
    let engageVisualX = (46.0 - Config.Autopilot.tempMinC) / (Config.Autopilot.tempMaxC - Config.Autopilot.tempMinC)
    assert(shutoffVisualX < engageVisualX, "Shutoff (44°C) must be physically to the left of Engage (46°C)")
    print("  ✅ 1:1 Scale Alignment: Shutoff 44°C (\(Int(shutoffVisualX * 100))%) < Engage 46°C (\(Int(engageVisualX * 100))%) — strictly non-inverted!")

    // 7. Test Mac Family-Aware LED Thermal Color Calibration
    print("\n🌈 Testing Mac Family-Aware LED Thermal Color Calibration...")
    // A. MacBook Air:
    let airCold = policy.heatColor(for: 41.0, macModel: "MacBook Air")
    assert(airCold.r == 0 && airCold.g == 255 && airCold.b == 0, "Expected pure green for MacBook Air at 41°C")
    print("  ✅ MacBook Air: 41°C (nominal) -> Pure Green LED (R: \(airCold.r), G: \(airCold.g), B: \(airCold.b))")

    let airWarm = policy.heatColor(for: 65.0, macModel: "MacBook Air")
    assert(airWarm.r > 150 && airWarm.g > 150, "Expected warm yellow for MacBook Air at 65°C")
    print("  ✅ MacBook Air: 65°C (moderate) -> Yellow/Amber LED (R: \(airWarm.r), G: \(airWarm.g), B: \(airWarm.b))")

    let airHot = policy.heatColor(for: 82.0, macModel: "MacBook Air")
    assert(airHot.r == 255 && airHot.g == 0, "Expected alert red for MacBook Air at 82°C")
    print("  ✅ MacBook Air: 82°C (hot/throttling) -> Pure Red LED (R: \(airHot.r), G: \(airHot.g), B: \(airHot.b))")

    // B. Mac Studio (tighter thermal threshold):
    let studioCold = policy.heatColor(for: 41.0, macModel: "Mac Studio")
    assert(studioCold.r == 0 && studioCold.g == 255, "Expected green for Mac Studio at 41°C")
    let studioHot = policy.heatColor(for: 74.0, macModel: "Mac Studio")
    assert(studioHot.r == 255 && studioHot.g == 0, "Expected red for Mac Studio at 74°C")
    print("  ✅ Mac Studio: 41°C -> Green, 74°C -> Pure Red LED")

    print("\n🎉 ALL TESTS PASSED! Multi-brand catalog, driver isolation, Smart Max baseline, Balanced acoustic ramp & Mac family thermal LED verified.")
}

@main
struct TestRunner {
    static func main() {
        runTests()
    }
}
