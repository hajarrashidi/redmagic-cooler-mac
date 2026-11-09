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

    // 5. AutopilotPolicy Smart Max, 30% Active Floor & Configurable Shutoff
    print("\n🧠 Testing Autopilot Smart Max 30% Active Floor & Shutoff Cutoff...")
    let policy = AutopilotPolicy(engageC: 50.0, shutoffC: 38.0, minFanPercent: 30, dwell: 0, hysteresisC: 5.0)
    policy.setProfile(.smartMax)

    // A. Mac is hot (50°C >= engage 50°C): MUST ENGAGE MAX (100% fan)
    var dec = policy.evaluate(thermalState: .nominal, dieC: 50.0, now: 1000)
    assert(dec.tier.mode == .max && dec.tier.fanPercent == 100, "Expected cooler max at 50°C")
    print("  ✅ High Heat: 50°C -> Cooler engages at MAX (100% fan)")

    // B. Mac cools down to 42°C (between shutoff 38°C and engage 50°C): MUST RUN AT 30% MIN POWER
    dec = policy.evaluate(thermalState: .nominal, dieC: 42.0, now: 1001)
    assert(dec.tier.mode == .low && dec.tier.fanPercent == 30, "Expected cooler active at min 30% fan at 42°C, got \(dec.tier.fanPercent)%")
    print("  ✅ Active Floor: 42°C -> Cooler stays active at MINIMUM POWER (30% fan)")

    // C. Mac cools all the way down to 37°C (< 38°C shutoff threshold): MUST SHUT OFF COMPLETELY
    dec = policy.evaluate(thermalState: .nominal, dieC: 37.0, now: 1002)
    assert(dec.tier.mode == .off && dec.tier.fanPercent == 0, "Expected cooler off when Mac drops below 38°C shutoff threshold")
    print("  ✅ Cold Cutoff: 37°C (< 38°C) -> Cooler shuts OFF completely (0% fan / Standby)")

    // D. Test user-customized shutoff and min fan percent:
    policy.setShutoff(40.0)
    policy.setMinFanPercent(40)
    print("  ✅ Configured custom shutoff to 40°C and min fan to 40%")

    // At 42°C, it should run at 40% fan:
    dec = policy.evaluate(thermalState: .nominal, dieC: 42.0, now: 1003)
    assert(dec.tier.mode == .low && dec.tier.fanPercent == 40, "Expected cooler at 40% fan")
    print("  ✅ Custom Min Fan: 42°C -> Cooler runs at configured 40% fan")

    // At 39°C (< 40°C), it should shut off:
    dec = policy.evaluate(thermalState: .nominal, dieC: 39.0, now: 1004)
    assert(dec.tier.mode == .off && dec.tier.fanPercent == 0, "Expected cooler off below custom 40°C shutoff")
    print("  ✅ Custom Shutoff: 39°C (< 40°C) -> Cooler shuts OFF completely (0% fan)")

    print("\n🎉 ALL TESTS PASSED! Multi-brand catalog, driver isolation & Smart Max active floor verified.")
}

runTests()
