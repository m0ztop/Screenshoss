import AppKit
import AVFoundation
import Foundation

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: ShelfPanelController?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var placementItems: [ShelfPresentationMode: NSMenuItem] = [:]
    private var startupSoundPlayer: AVAudioPlayer?
    private let showNotificationName = Notification.Name("com.mert.screenshoss.show")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard !terminateIfAnotherInstanceIsRunning() else { return }
        registerShowNotification()
        playStartupSound()

        let library = ScreenshotLibrary()
        let panelController = ShelfPanelController(library: library)
        self.panelController = panelController
        panelController.show()

        setupStatusItem()
        registerLaunchAgentIfNeeded()
    }

    private func terminateIfAnotherInstanceIsRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existingApps = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        guard !existingApps.isEmpty else { return false }

        DistributedNotificationCenter.default().postNotificationName(
            showNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        NSApp.terminate(nil)
        return true
    }

    private func registerShowNotification() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showFromDistributedNotification),
            name: showNotificationName,
            object: nil
        )
    }

    @objc private func showFromDistributedNotification(_ notification: Notification) {
        panelController?.show()
    }

    private func playStartupSound() {
        guard let url = startupSoundURL() else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = 0.6
        player.prepareToPlay()
        player.play()
        startupSoundPlayer = player
    }

    private func startupSoundURL() -> URL? {
        if let bundledURL = Bundle.main.url(forResource: "app-start", withExtension: "mp3") {
            return bundledURL
        }

        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/app-start.MP3")
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
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

        let positionItem = NSMenuItem(title: "Notch Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        placementItems = [:]
        for mode in ShelfPresentationMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(setShelfPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            positionMenu.addItem(item)
            placementItems[mode] = item
        }
        menu.addItem(positionItem)
        menu.setSubmenu(positionMenu, for: positionItem)
        updatePlacementMenuState()

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
            updatePlacementMenuState()
            menu.popUp(positioning: nil, at: .zero, in: button)
        } else {
            panelController?.show()
        }
    }

    @objc private func openShoss() {
        panelController?.show()
    }

    @objc private func setShelfPosition(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = ShelfPresentationMode(rawValue: rawValue) else {
            return
        }
        panelController?.setPresentationMode(mode)
        updatePlacementMenuState()
    }

    private func updatePlacementMenuState() {
        let currentMode = panelController?.presentationMode
        for (mode, item) in placementItems {
            item.state = mode == currentMode ? .on : .off
        }
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
