import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = AppState(forceDemo: CommandLine.arguments.contains("--demo"))
    private let nav = Navigation()
    private var statusBar: StatusBarController?
    private var window: NSWindow?
    private var windowVisible = false
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        statusBar = StatusBarController(
            state: state,
            openControlCenter: { [weak self] in self?.showControlCenter(page: .fans) },
            openSettings: { [weak self] in self?.showControlCenter(page: .settings) },
            quit: { NSApp.terminate(nil) })
        state.onUpdate = { [weak self] in self?.statusBar?.refresh() }
        state.start()

        // Hand the fans back on any normal termination signal; the helper's watchdog covers crashes.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.state.tick()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlCenter(page: .fans)
        return true
    }

    // MARK: Control center window

    func showControlCenter(page: ControlCenterPage) {
        nav.page = page
        if window == nil { window = makeWindow() }
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !windowVisible {
            windowVisible = true
            state.surfaceVisibilityChanged(visible: true)
        }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Fan Control"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentMinSize = NSSize(width: 900, height: 620)
        w.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active

        let host = NSHostingView(rootView: ControlCenterView().environment(state).environment(nav))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        w.contentView = effect
        w.center()
        w.setFrameAutosaveName("ControlCenter")
        return w
    }

    func windowWillClose(_ notification: Notification) {
        if windowVisible {
            windowVisible = false
            state.surfaceVisibilityChanged(visible: false)
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
