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

    // 5. AutopilotPolicy Smart Max Fast-Attack Boost & Configurable Shutoff
    print("\n🧠 Testing Autopilot Smart Max Fast-Attack Boost & Shutoff Cutoff...")
    let policy = AutopilotPolicy(engageC: 50.0, shutoffC: 38.0, minFanPercent: 40)
    policy.setProfile(.smartMax)

    // A. Mac is hot (50°C >= engage 50°C): MUST ENGAGE MAX (100% fan)
    var dec = policy.evaluate(thermalState: .nominal, dieC: 50.0, now: 1000)
    assert(dec.tier.mode == .max && dec.tier.fanPercent == 100, "Expected cooler max at 50°C")
    print("  ✅ Smart Max High Heat: 50°C -> Cooler engages at MAX (100% fan)")

    // B. Mac at 41°C (progress = (41-38)/(50-38) = 0.25, sqrt(0.25)=0.5, 40 + 0.5*60 = 70%):
    dec = policy.evaluate(thermalState: .nominal, dieC: 41.0, now: 1001)
    assert(dec.tier.fanPercent == 70, "Expected Smart Max fast-attack at 70% fan at 41°C, got \(dec.tier.fanPercent)%")
    print("  ✅ Smart Max Fast-Attack: 41°C -> Fast-attack delivers 70% fan")

    // C. Mac cools all the way down to 37°C (< 38°C shutoff threshold): MUST SHUT OFF COMPLETELY
    dec = policy.evaluate(thermalState: .nominal, dieC: 37.0, now: 1002)
    assert(dec.tier.mode == .off && dec.tier.fanPercent == 0, "Expected cooler off when Mac drops below 38°C shutoff threshold")
    print("  ✅ Smart Max Cold Cutoff: 37°C (< 38°C) -> Cooler shuts OFF completely (0% fan / Standby)")

    // D. Test user-customized base fan percent to 55%:
    policy.setMinFanPercent(55)
    print("  ✅ Configured custom base fan to 55%")

    // At 41°C with base 55% (55 + 0.5*45 = 77.5 -> 80%):
    dec = policy.evaluate(thermalState: .nominal, dieC: 41.0, now: 1003)
    assert(dec.tier.fanPercent == 80, "Expected cooler at 80% fan with 55% base, got \(dec.tier.fanPercent)%")
    print("  ✅ Smart Max Custom Base: 41°C -> Cooler runs at configured 80% fan")

    // At 37°C (< 38°C), it should shut off:
    dec = policy.evaluate(thermalState: .nominal, dieC: 37.0, now: 1004)
    assert(dec.tier.mode == .off && dec.tier.fanPercent == 0, "Expected cooler off below 38°C shutoff")
    print("  ✅ Smart Max Shutoff: 37°C (< 38°C) -> Cooler shuts OFF completely (0% fan)")

    // 6. Test Balanced Dynamic Acoustic Ramp & Shutoff
    print("\n🧠 Testing Autopilot Balanced Dynamic Acoustic Ramp & Shutoff...")
    let balanced = AutopilotPolicy(engageC: 50.0, shutoffC: 38.0, minFanPercent: 40)
    balanced.setProfile(.balanced)

    // A. Cold Mac (37°C < shutoff 38°C): MUST SHUT OFF COMPLETELY (0% fan)
    var bDec = balanced.evaluate(thermalState: .nominal, dieC: 37.0)
    assert(bDec.tier.mode == .off && bDec.tier.fanPercent == 0, "Expected Balanced to shut off below shutoff threshold")
    print("  ✅ Balanced Cold Cutoff: 37°C (< 38°C) -> Cooler shuts OFF completely (0% fan / Standby)")

    // B. At shutoff boundary (38°C): starts at 40% fan (user-chosen min power)
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 38.0)
    assert(bDec.tier.mode == .low && bDec.tier.fanPercent == 40, "Expected Balanced at 40% at 38°C, got \(bDec.tier.fanPercent)%")
    print("  ✅ Balanced Acoustic Floor: 38°C -> Starts gently at 40% fan")

    // C. At 41°C (progress = 0.25, 40 + 0.25*60 = 55%):
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 41.0)
    assert(bDec.tier.fanPercent == 55, "Expected Balanced linear ramp at 55% at 41°C, got \(bDec.tier.fanPercent)%")
    print("  ✅ Balanced Acoustic Ramp: 41°C -> Precisely 55% fan")

    // Verify Smart Max delivers MORE cooling than Balanced at same 41°C temperature:
    let smDec = policy.evaluate(thermalState: .nominal, dieC: 41.0)
    assert(smDec.tier.fanPercent > bDec.tier.fanPercent, "Smart Max (\(smDec.tier.fanPercent)%) must deliver higher cooling than Balanced (\(bDec.tier.fanPercent)%) at same temp")
    print("  ✅ Multi-Tier Verification: Smart Max (\(smDec.tier.fanPercent)%) > Balanced (\(bDec.tier.fanPercent)%) at 41°C")

    // D. At 50°C (engage threshold): 100% max fan
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 50.0)
    assert(bDec.tier.mode == .max && bDec.tier.fanPercent == 100, "Expected Balanced 100% at engage threshold")
    print("  ✅ Balanced Full Power: 50°C (engage) -> 100% MAX fan")

    // E. Change shutoff threshold in Balanced to 42°C: at 41°C it MUST now be OFF!
    balanced.setShutoff(42.0)
    bDec = balanced.evaluate(thermalState: .nominal, dieC: 41.0)
    assert(bDec.tier.mode == .off && bDec.tier.fanPercent == 0, "Expected Balanced to shut off at 41°C when shutoff is 42°C")
    print("  ✅ Balanced Custom Shutoff: 41°C (< custom 42°C) -> Cooler immediately shuts OFF")

    print("\n🎉 ALL TESTS PASSED! Multi-brand catalog, driver isolation, Smart Max fast-attack & Balanced acoustic curve verified.")
}

runTests()
