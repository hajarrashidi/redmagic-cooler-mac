import Foundation
import CoreBluetooth

// Standalone test script to verify profile matching and driver isolation
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
            assert(matched == nil, "Expected no match for '\(name)', got '\(matched!.id)'")
            print("  ✅ Ignored: '\(name)' correctly identified as non-cooler")
        }
    }

    // 2. Black Shark Manufacturer Data Identification
    let bsMfgData = Data([0x8F, 0x03, 0x01, 0x02])
    let bsAdv = [CBAdvertisementDataManufacturerDataKey: bsMfgData]
    let bsMatched = DeviceProfile.matching(deviceName: "BR42-Cooler", advertisementData: bsAdv)
    assert(bsMatched != nil && bsMatched!.brand == "Black Shark", "Manufacturer data matching failed for Black Shark")
    print("  ✅ Manufacturer Data: Black Shark [0x8F, 0x03] -> \(bsMatched!.modelName)")

    // 3. Flydigi Service UUID Identification
    let fdServices = [CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")]
    let fdAdv = [CBAdvertisementDataServiceUUIDsKey: fdServices]
    let fdMatched = DeviceProfile.matching(deviceName: "Cooler-Unknown", advertisementData: fdAdv)
    assert(fdMatched != nil && fdMatched!.brand == "Flydigi", "Service UUID matching failed for Flydigi")
    print("  ✅ Service UUID: Flydigi FFE0 -> \(fdMatched!.modelName)")

    // 4. Driver Instantiation and Isolation
    for profile in DeviceProfile.all {
        let driver = profile.makeDriver()
        assert(driver.profile.id == profile.id, "Driver profile mismatch for \(profile.id)")
        assert(driver.serviceUUID == profile.serviceUUID, "Driver serviceUUID mismatch for \(profile.id)")
        print("  ✅ Driver: \(profile.id) -> \(type(of: driver)) with Service \(driver.serviceUUID.uuidString)")
    }

    // 5. Vendor hints recognition for unsupported coolers
    let vendorTests = ["iQOO Radiator 2", "OnePlus 45W Liquid Cooler", "Memo Cooler CX01"]
    for v in vendorTests {
        assert(DeviceProfile.looksLikeVendorDevice(deviceName: v), "Expected vendor hint hit for '\(v)'")
        print("  ✅ Vendor Hint: '\(v)' recognized as candidate cooler")
    }

    print("\n🎉 ALL TESTS PASSED! Multi-brand cooler support & driver isolation 100% verified.")
}

runTests()
