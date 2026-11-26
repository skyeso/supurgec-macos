import SwiftUI
import AppKit
import Combine
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static let showMainNotification = Notification.Name("com.eso.supurgec.showMainWindow")

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    /// Hem --background argümanını hem de macOS'un oturum açılışında gönderdiği
    /// resmi keyAELaunchedAsLogInItem ('lgit') AppleEvent bayrağını algılar.
    private var launchedSilentlyInBackground: Bool {
        if CommandLine.arguments.contains("--background") {
            return true
        }
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           let prop = event.paramDescriptor(forKeyword: keyAEPropData),
           prop.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Zaten çalışan bir Süpürgeç örneği varsa ona "ana pencereyi aç" sinyali gönder ve ikincil kopyayı kapat
        if let bundleID = Bundle.main.bundleIdentifier {
            let me = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != me }
            if let existing = others.first {
                if !launchedSilentlyInBackground {
                    DistributedNotificationCenter.default().postNotificationName(
                        Self.showMainNotification,
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                    existing.activate(options: [.activateAllWindows])
                }
                NSApp.terminate(nil)
                return
            }
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalShowRequest(_:)),
            name: Self.showMainNotification,
            object: nil
        )

        setupMainMenu()

        LaunchAtLoginService.removeLegacyPlistIfPresent()
        if UserDefaults.standard.object(forKey: "login.sm.initialized") == nil {
            UserDefaults.standard.set(true, forKey: "login.sm.initialized")
            LaunchAtLoginService.setEnabled(true)
        }

        setupStatusBarItem()

        if launchedSilentlyInBackground {
            NSApp.setActivationPolicy(.accessory)
        } else {
            showMainWindow()
        }
    }

    @objc private func handleExternalShowRequest(_ note: Notification) {
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Spotlight, Finder veya Uygulamalar'dan tıklandığında her zaman gerçek Süpürgeç penceresini aç!
        showMainWindow()
        return true
    }

    // MARK: - Standart macOS Menü Çubuğu (Cmd+Q, Cmd+W, Cmd+C/V/A, Cmd+,)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Uygulama Menüsü (Süpürgeç)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let settingsItem = NSMenuItem(title: "Ayarlar…", action: #selector(openSettingsMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "Süpürgeç'i Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        let closeItem = NSMenuItem(title: "Pencereyi Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(closeItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Süpürgeç'ten Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        // 2. Düzen Menüsü (Arama kutularında Kopyala/Yapıştır/Tümünü Seç kısayolları için)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Düzen")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsMenuAction() {
        showMainWindow(navigatingTo: .settings)
    }

    // MARK: - Ana Pencere Yönetimi (Asla Boş Gri Settings Penceresi Açmaz!)

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
enum SupurgecMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
