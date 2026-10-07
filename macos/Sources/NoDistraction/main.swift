import AppKit

// App solo nella barra dei menu (LSUIElement): niente finestre né Dock.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
