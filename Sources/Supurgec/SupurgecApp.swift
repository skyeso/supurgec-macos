import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private var launchedSilentlyInBackground: Bool {
        CommandLine.arguments.contains("--background")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Çift örnek (iki menü çubuğu ikonu) oluşmasını engelle
        if let bundleID = Bundle.main.bundleIdentifier {
            let me = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != me }
            if let existing = others.first {
                if !launchedSilentlyInBackground {
                    existing.activate(options: [.activateAllWindows])
                }
                NSApp.terminate(nil)
                return
            }
        }

        // İlk kurulumda oturum açılışında üst barda başlatmayı varsayılan olarak etkinleştir
        if UserDefaults.standard.object(forKey: "login.initialized") == nil {
            UserDefaults.standard.set(true, forKey: "login.initialized")
            LaunchAtLoginService.setEnabled(true)
        }

        setupStatusBarItem()

        if launchedSilentlyInBackground {
            // Bilgisayar açılışında: Pencere açma, Dock'ta gösterme — yalnızca üst barda çalış!
            NSApp.setActivationPolicy(.accessory)
        } else {
            // Kullanıcı uygulamaya kendisi tıkladığında: Ana pencereyi ve Dock ikonunu aç
            showMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - Ana Pencere Yönetimi (Dock Gizleme & Bellek Tasarrufu)

    func showMainWindow(navigatingTo module: NavModule? = nil) {
        NSApp.setActivationPolicy(.regular)

        if mainWindow == nil {
            let hosting = NSHostingController(rootView: MainWindowView())
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "Süpürgeç"
            win.contentViewController = hosting
            win.delegate = self
            win.isReleasedWhenClosed = false
            win.setFrameAutosaveName("SupurgecMainWindow")
            win.center()
            configureWindowAppearance(win)
            mainWindow = win
        }

        if let win = mainWindow {
            configureWindowAppearance(win)
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        if let module {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .navigateToModule, object: module)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === mainWindow else { return }
        // Kırmızı çarpıya (veya Cmd+W) basıldığında pencereyi bellekten düşür ve Dock'tan gizle!
        mainWindow?.contentViewController = nil
        mainWindow = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func configureWindowAppearance(_ window: NSWindow) {
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
}

@main
struct SupurgecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings sahnesi sayesinde SwiftUI açılışta zorla pencere oluşturmaz;
        // pencere açılışı tamamen AppDelegate (--background kontrolü) tarafından yönetilir!
        Settings {
            EmptyView()
        }
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
