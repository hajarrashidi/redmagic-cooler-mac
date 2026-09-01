import Foundation

/// Where the link to the cooler currently stands.
///
/// Richer than a `Bool` because most of these states need distinct UI: the menu
/// bar, the status card and the Connect button each say something different
/// while a connection is being established, and "Bluetooth is off" is a very
/// different message from "still scanning".
enum ConnectionPhase: Equatable {
    /// No link, and nothing in flight — either at launch or after the user
    /// explicitly disconnected.
    case idle
    case bluetoothOff
    case bluetoothUnauthorized
    case scanning
    case connecting(name: String?)
    case discoveringServices
    case discoveringCharacteristics
    /// Connected with every characteristic resolved — the only usable state.
    case ready
    /// A link was lost or timed out; a retry is scheduled.
    case reconnecting

    var isConnected: Bool { self == .ready }

    /// True while an attempt is in flight, so the UI can refuse to start a
    /// second one — restarting a scan mid-connect cancels the attempt already
    /// running.
    var isBusy: Bool {
        switch self {
        case .connecting, .discoveringServices, .discoveringCharacteristics, .reconnecting:
            return true
        default:
            return false
        }
    }

    /// Sentence-form description for the status card.
    var statusText: String {
        switch self {
        case .idle:                       return "Not connected"
        case .bluetoothOff:               return "Bluetooth is off"
        case .bluetoothUnauthorized:      return "Bluetooth permission required"
        case .scanning:                   return "Scanning for cooler…"
        case .connecting(let name):       return "Connecting to \(name ?? "cooler")…"
        case .discoveringServices:        return "Discovering services…"
        case .discoveringCharacteristics: return "Reading settings…"
        case .ready:                      return "Connected"
        case .reconnecting:               return "Reconnecting…"
        }
    }

    /// Label for the Connect menu item. `nil` means the item should read
    /// "Connect" and be clickable.
    var connectItemTitle: String? {
        switch self {
        case .connecting, .discoveringServices, .discoveringCharacteristics:
            return "Connecting…"
        case .reconnecting:          return "Reconnecting…"
        case .scanning:              return "Searching…"
        case .bluetoothOff:          return "Turn on Bluetooth to connect"
        case .bluetoothUnauthorized: return "Allow Bluetooth in System Settings"
        default:                     return nil
        }
    }

}
