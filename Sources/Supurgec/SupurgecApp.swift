import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    var openMainWindowHandler: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupStatusBarItem()
        observeWindowClosing()
        configureWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.configureWindows()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Ana pencere kapatıldığında uygulama kapanmaz; üst barda çalışmaya devam eder.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Uygulamalar veya Spotlight'tan tekrar tıklandığında pencereyi geri aç ve Dock'ta göster.
        if !flag {
            showMainWindow()
        }
        return true
    }

    private func isMainAppWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        let cls = window.className
        if cls.contains("StatusBar") || cls.contains("Popover") || cls.contains("MenuBar") {
            return false
        }
        return true
    }

    private func observeWindowClosing() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let closedWindow = note.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isMainAppWindow(closedWindow) else { return }
                // Pencere kapandıktan hemen sonra görünür başka ana pencere kalmadıysa Dock'tan gizle!
                try? await Task.sleep(for: .milliseconds(80))
                let anyMainVisible = NSApp.windows.contains { $0.isVisible && self.isMainAppWindow($0) }
                if !anyMainVisible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func configureWindows() {
        for window in NSApp.windows where isMainAppWindow(window) {
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.065, green: 0.070, blue: 0.125, alpha: 1.0)
        }
    }

    // MARK: - Kişiselleştirilebilir ve Sabit Genişlikli Menü Çubuğu Öğesi

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        if let button = item.button {
            button.alignment = .center
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = NSSize(width: 384, height: 462)

        refreshStatusBarAppearance()

        SystemMonitor.shared.$menuBarTick
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusBarTextOnly()
            }
            .store(in: &cancellables)

        MenuBarSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    SystemMonitor.shared.updateFull()
                    self?.refreshStatusBarAppearance()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshStatusBarAppearance() {
        guard let item = statusItem, let button = item.button else { return }
        let settings = MenuBarSettings.shared

        if let symbol = settings.iconChoice.symbolName,
           let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Süpürgeç") {
            img.isTemplate = true
            button.image = img
            button.imagePosition = settings.maxSampleTitle.isEmpty ? .imageOnly : .imageLeading
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }

        item.length = settings.fixedBarWidth(for: settings.maxSampleTitle)
        button.title = settings.formattedTitle(monitor: SystemMonitor.shared)
    }

    private func refreshStatusBarTextOnly() {
        guard let button = statusItem?.button else { return }
        button.title = MenuBarSettings.shared.formattedTitle(monitor: SystemMonitor.shared)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            SystemMonitor.shared.beginInteractiveSession()
            let hc = NSHostingController(
                rootView: MenuBarMonitorView { [weak self] targetModule in
                    self?.popover.performClose(nil)
                    self?.showMainWindow(navigatingTo: targetModule)
                }
            )
            hc.sizingOptions = [.preferredContentSize]
            popover.contentViewController = hc
            popover.contentSize = NSSize(width: 384, height: 462)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        SystemMonitor.shared.endInteractiveSession()
    }

    func showMainWindow(navigatingTo module: NavModule? = nil) {
        // Ana pencere açılırken uygulamayı tekrar Dock'ta görünür (.regular) yap!
        NSApp.setActivationPolicy(.regular)

        if let existing = NSApp.windows.first(where: { isMainAppWindow($0) && $0.canBecomeMain }) {
            configureWindows()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let module {
                NotificationCenter.default.post(name: .navigateToModule, object: module)
            }
        } else {
            openMainWindowHandler?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                self.configureWindows()
                if let win = NSApp.windows.first(where: { self.isMainAppWindow($0) }) {
                    win.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
                if let module {
                    NotificationCenter.default.post(name: .navigateToModule, object: module)
                }
            }
        }
    }
}

@main
struct SupurgecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Süpürgeç", id: "main") {
            MainWindowView()
                .onAppear {
                    appDelegate.openMainWindowHandler = { openWindow(id: "main") }
                    appDelegate.configureWindows()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Ayarlar…") {
                    appDelegate.showMainWindow(navigatingTo: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
