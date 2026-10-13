import AppKit
import SwiftUI
import FanCore

/// Owns the menu bar items (fan speed, temperature) and the popover they open.
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let state: AppState
    private let popover = NSPopover()
    private var fanItem: NSStatusItem?
    private var tempItem: NSStatusItem?
    private var fanSignature = ""
    private var tempSignature = ""
    private var popoverVisible = false

    private let openControlCenter: () -> Void
    private let openSettings: () -> Void
    private let quit: () -> Void

    init(state: AppState, openControlCenter: @escaping () -> Void, openSettings: @escaping () -> Void,
         quit: @escaping () -> Void) {
        self.state = state
        self.openControlCenter = openControlCenter
        self.openSettings = openSettings
        self.quit = quit
        super.init()

        let root = PopoverView(
            openControlCenter: { [weak self] in self?.popover.performClose(nil); openControlCenter() },
            openSettings: { [weak self] in self?.popover.performClose(nil); openSettings() },
            quit: quit)
            .environment(state)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        refresh()
    }

    // MARK: Items

    func refresh() {
        let s = state.config.settings
        var wantFan = s.showFanItem && state.hasFans
        let wantTemp = s.showTempItem
        let iconOnly = !wantFan && !wantTemp   // never leave the user with no way to reach the app
        if iconOnly { wantFan = true }

        sync(&fanItem, wanted: wantFan)
        sync(&tempItem, wanted: wantTemp)
        if wantFan { updateFanItem(iconOnly: iconOnly) }
        if wantTemp { updateTempItem() }
    }

    private func sync(_ item: inout NSStatusItem?, wanted: Bool) {
        if wanted, item == nil {
            let new = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            new.button?.target = self
            new.button?.action = #selector(clicked(_:))
            new.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item = new
        } else if !wanted, let existing = item {
            NSStatusBar.system.removeStatusItem(existing)
            item = nil
        }
    }

    private func updateFanItem(iconOnly: Bool) {
        guard let button = fanItem?.button else { return }
        let s = state.config.settings
        let rpm = state.averageRPM
        let style: WidgetStyle = iconOnly ? .iconText : s.fanWidget
        let fraction = state.fans.first.map { $0.limits.percent(forRPM: state.averageRPM ?? $0.rpm) / 100 } ?? 0
        let tint: NSColor? = s.colorCodedMenuBar ? NSColor(Theme.accent) : nil
        let text = iconOnly ? "" : (rpm.map { String(Int($0.rounded())) } ?? "–")

        let signature = "\(style.rawValue)|\(text)|\(tint != nil)|\(Int(fraction * 20))|\(state.history["fan0"]?.last.map { Int($0 / 50) } ?? 0)"
        guard signature != fanSignature else { return }
        fanSignature = signature

        switch style {
        case .iconText:
            button.image = WidgetRenderer.tinted(WidgetRenderer.symbol("fan"), tint)
        case .sparkline:
            let first = state.fans.first
            button.image = WidgetRenderer.sparkline(values: state.history["fan0"] ?? [],
                                                    range: first.map { $0.limits.min...$0.limits.max }, color: tint)
        case .bar:
            button.image = WidgetRenderer.bar(fraction: fraction, color: tint)
        case .textOnly:
            button.image = nil
        }
        button.imagePosition = text.isEmpty ? .imageOnly : (button.image == nil ? .noImage : .imageLeading)
        button.attributedTitle = text.isEmpty ? NSAttributedString() : WidgetRenderer.title(text)
        button.toolTip = state.fans.map { "\($0.name): \(Int($0.rpm.rounded())) RPM" }.joined(separator: "\n")
    }

    private func updateTempItem() {
        guard let button = tempItem?.button else { return }
        let s = state.config.settings
        let temp = state.menuBarTemperature
        let tint: NSColor? = (s.colorCodedMenuBar ? temp.map { Theme.nsHeat($0) } : nil)
        let text = temp.map { String(Int(s.unit.convert($0).rounded())) + "°" } ?? "–"
        let fraction = temp.map { ($0 - 20) / 80 } ?? 0

        let signature = "\(s.tempWidget.rawValue)|\(text)|\(tint?.hashValue ?? 0)|\(state.history["menubar"]?.count ?? 0)|\(state.history["menubar"]?.last.map { Int($0) } ?? 0)"
        guard signature != tempSignature else { return }
        tempSignature = signature

        switch s.tempWidget {
        case .iconText:
            button.image = WidgetRenderer.tinted(WidgetRenderer.symbol("thermometer.medium"), tint)
        case .sparkline:
            button.image = WidgetRenderer.sparkline(values: state.history["menubar"] ?? [], range: nil, color: tint)
        case .bar:
            button.image = WidgetRenderer.bar(fraction: fraction, color: tint)
        case .textOnly:
            button.image = nil
        }
        button.imagePosition = button.image == nil ? .noImage : .imageLeading
        button.attributedTitle = WidgetRenderer.title(text, color: tint)
        button.toolTip = [SensorCategory.cpu, .gpu].compactMap { c in
            state.temps.average(c).map { "\(c.title): \(state.format($0))" }
        }.joined(separator: "\n")
    }

    // MARK: Interaction

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: sender)
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        for profile in state.allProfiles {
            let item = NSMenuItem(title: profile.name, action: #selector(applyProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = (profile.id == state.config.activeProfileID && !state.isModified) ? .on : .off
            item.image = NSImage(systemSymbolName: profile.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Control Center", action: #selector(openCC), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Fan Control", action: #selector(quitApp), keyEquivalent: "q").target = self

        let owner = (button === fanItem?.button) ? fanItem : tempItem
        owner?.menu = menu
        button.performClick(nil)
        owner?.menu = nil
    }

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let p = state.allProfiles.first(where: { $0.id == id }) else { return }
        state.apply(profile: p)
    }
    @objc private func openCC() { openControlCenter() }
    @objc private func quitApp() { quit() }

    // MARK: NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        guard !popoverVisible else { return }
        popoverVisible = true
        state.surfaceVisibilityChanged(visible: true)
    }

    func popoverDidClose(_ notification: Notification) {
        guard popoverVisible else { return }
        popoverVisible = false
        state.surfaceVisibilityChanged(visible: false)
    }
}
