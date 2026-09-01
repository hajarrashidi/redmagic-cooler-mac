import Foundation

/// Registers the app as a macOS login item.
///
/// Implemented with AppleScript against System Events rather than the modern
/// `SMAppService`, which requires the app to be a properly signed, notarised
/// bundle in `/Applications`. This app is built and run in place from the repo,
/// where `SMAppService` silently refuses to register. The trade-off is that the
/// first call raises an Automation consent prompt.
enum LoginItem {

    /// Must match the bundle name — System Events keys login items by it.
    private static let name = "RedMagic Cooler"

    static var isEnabled: Bool {
        let result = run("""
            tell application "System Events"
                return exists (login item "\(name)")
            end tell
            """)
        return result?.booleanValue ?? false
    }

    /// Escapes a value for interpolation inside a quoted AppleScript string.
    /// The bundle path is wherever the user put the app; one `"` in a folder
    /// name would otherwise end the string mid-path and break the script.
    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func setEnabled(_ enabled: Bool) {
        let script = enabled
            ? """
              tell application "System Events"
                  if not (exists login item "\(name)") then
                      make new login item at end with properties ¬
                          {path:"\(escaped(Bundle.main.bundlePath))", name:"\(name)", hidden:false}
                  end if
              end tell
              """
            : """
              tell application "System Events"
                  if exists login item "\(name)" then
                      delete (every login item whose name is "\(name)")
                  end if
              end tell
              """
        _ = run(script)
    }

    /// Runs a script, returning `nil` on error. Errors are logged rather than
    /// surfaced: the only realistic cause is the user declining the Automation
    /// prompt, and the checkbox reverting already tells them it didn't take.
    @discardableResult
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            EventLogger.record("login item — AppleScript failed: \(error)")
            return nil
        }
        return result
    }
}
