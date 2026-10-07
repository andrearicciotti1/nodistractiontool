import AppKit
import Combine
import SwiftUI

/// Pannello che si apre dall'icona nella barra dei menu. Sostituisce la
/// finestra di MenuBarExtra, che su macOS recenti aggiunge un proprio fondo
/// trasparente più grande del contenuto e non si adatta quando questo cambia.
final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    /// Porta il pannello alla misura del contenuto tenendo fermo il bordo in alto.
    func fit(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }
        setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    /// Mostra il pannello sotto `button`, dentro lo schermo.
    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = anchor.midX - frame.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - frame.width - 8)
        setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 6))
        makeKeyAndOrderFront(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Icona nella barra dei menu e apertura/chiusura del pannello.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: StatusPanel!
    private var clickMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        panel = StatusPanel(content: MenuView(model: model) { [weak self] size in
            self?.panel?.fit(to: size)
        })
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in self?.closePanel() }
            .store(in: &subscriptions)

        model.$phase
            .map { _ in () }
            .merge(with: Just(()))
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateIcon() }
            .store(in: &subscriptions)

        DebugSnapshot.runIfRequested(
            open: { [weak self] in self?.openPanel() },
            panel: { [weak self] in self?.panel },
            changeContent: { [weak self] in self?.model.debugSetLastAction("Riga di prova molto lunga per verificare che il pannello si allunghi quando il contenuto cresce") }
        )
    }

    private func updateIcon() {
        let image = NSImage(systemSymbolName: model.menuIcon, accessibilityDescription: "No Distraction")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func togglePanel() {
        if panel.isVisible { closePanel() } else { openPanel() }
    }

    private func openPanel() {
        guard let button = statusItem.button else { return }
        panel.show(below: button)
        statusItem.button?.highlight(true)
        // Un clic fuori dal pannello (in altre app) lo chiude, come un menu.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

/// Diagnosi: con `--debug-snapshot <prefisso>` apre il pannello e ne salva
/// due immagini, prima e dopo aver cambiato l'altezza del contenuto, per
/// controllare la grafica senza aprirlo a mano.
enum DebugSnapshot {
    @MainActor
    static func runIfRequested(open: @escaping () -> Void, panel: @escaping () -> NSWindow?, changeContent: @escaping () -> Void) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--debug-snapshot"), index + 1 < args.count else { return }
        let prefix = args[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            open()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                save(panel(), to: prefix + "-1.png")
                changeContent()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    save(panel(), to: prefix + "-2.png")
                }
            }
        }
    }

    @MainActor
    private static func save(_ window: NSWindow?, to path: String) {
        guard let window else { return }
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let rect = window.frame.insetBy(dx: -20, dy: -20)
        let quartzRect = CGRect(x: rect.minX, y: screenTop - rect.maxY, width: rect.width, height: rect.height)
        guard let image = CGWindowListCreateImage(
            quartzRect, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]
        ) else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
        print("\(path): frame \(window.frame)")
    }
}
