import Foundation

/// A unified telemetry frame from any supported cooler's notification or polling channel.
struct CoolerTelemetry: Equatable {
    /// Cold plate temperature in °C — the face against the Mac (signed integer).
    let coldC: Int

    /// Hot side temperature in °C — the fin stack the fan exhausts through.
    let hotC: Int

    /// Ambient temperature in °C (if reported by hardware, else 0).
    let ambientC: Int

    /// Fan speed in RPM (absent on some older models/firmware).
    let fanRPM: Int?
}
