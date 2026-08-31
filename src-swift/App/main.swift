import AppKit

// Entry point. SIGTERM is handled in AppDelegate via a DispatchSourceSignal
// rather than a signal() handler here — almost nothing is safe to call from
// inside a real signal handler, and the handler this file used to install was
// overridden by that source moments later anyway.

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
