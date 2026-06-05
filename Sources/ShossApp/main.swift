import AppKit
import Foundation

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: ShelfPanelController?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let library = ScreenshotLibrary()
        let panelController = ShelfPanelController(library: library)
        self.panelController = panelController
        panelController.show()

        setupStatusItem()
        registerLaunchAgentIfNeeded()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshoss")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Screenshoss", action: #selector(openShoss), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())
        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Screenshoss", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            panelController?.show()
            return
        }
        if event.type == .rightMouseUp, let button = statusItem?.button, let menu = statusMenu {
            menu.popUp(positioning: nil, at: .zero, in: button)
        } else {
            panelController?.show()
        }
    }

    @objc private func openShoss() {
        panelController?.show()
    }

    @objc private func openScreenshotsFolder() {
        let storageURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screenshoss/Screenshots", isDirectory: true)
        NSWorkspace.shared.open(storageURL)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private func registerLaunchAgentIfNeeded() {
    guard Bundle.main.bundlePath.hasSuffix(".app") else {
        return
    }

    guard let executablePath = Bundle.main.executablePath else {
        print("[Screenshoss] Could not determine executable path for LaunchAgent")
        return
    }

    let agentDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    let plistURL = agentDir.appendingPathComponent("com.mert.screenshoss.plist")
    let legacyPlistURL = agentDir.appendingPathComponent("com.mert.shoss.plist")

    do {
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
    } catch {
        print("[Screenshoss] Could not create LaunchAgents directory: \(error)")
        return
    }

    let plist: [String: Any] = [
        "Label": "com.mert.screenshoss",
        "Program": executablePath,
        "RunAtLoad": true,
        "LimitLoadToSessionType": "Aqua",
    ]

    do {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    } catch {
        print("[Screenshoss] Could not write LaunchAgent plist: \(error)")
        return
    }

    if legacyPlistURL != plistURL {
        try? FileManager.default.removeItem(at: legacyPlistURL)
    }

    let uid = getuid()
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["bootstrap", "gui/\(uid)", plistURL.path]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        print("[Screenshoss] Could not bootstrap LaunchAgent: \(error)")
    }
}

@MainActor
enum ShossMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

ShossMain.main()
