import AppKit
import Combine
import Foundation

enum ShelfPresentationMode: String, CaseIterable, Hashable {
    case top
    case left
    case right

    var menuTitle: String {
        switch self {
        case .top: "Top Notch"
        case .left: "Left Notch"
        case .right: "Right Notch"
        }
    }
}

struct TrashUndoNotice: Equatable {
    let id = UUID()
    let itemCount: Int

    var message: String {
        itemCount == 1
            ? "Screenshot moved to Trash"
            : "\(itemCount) screenshots moved to Trash"
    }
}

private struct PendingTrashedScreenshot {
    let location: TrashedScreenshotLocation
    let wasFavorite: Bool
}

@MainActor
final class ScreenshotLibrary: ObservableObject {
    @Published private(set) var items: [ScreenshotItem] = []
    @Published private(set) var folders: [ScreenshotFolder] = []
    @Published var selectedItem: ScreenshotItem?
    @Published private(set) var selectedItemIDs: Set<URL> = []
    @Published var selectedFolderName: String?
    @Published var showingFavoritesOnly = false
    @Published var draggedItemURLs: Set<URL> = []
    @Published var searchText = ""
    @Published private(set) var trashUndoNotice: TrashUndoNotice?
    @Published var presentationMode: ShelfPresentationMode {
        didSet {
            UserDefaults.standard.set(presentationMode.rawValue, forKey: Self.presentationModeDefaultsKey)
        }
    }
    @Published var isExpanded = false {
        didSet {
            guard oldValue != isExpanded else { return }
            expansionDidChange?(isExpanded)
        }
    }

    var expansionDidChange: ((Bool) -> Void)?
    var shouldCollapseAfterHoverExit: (() -> Bool)?
    var closeAction: (() -> Void)?
    var modalWillOpen: (() -> Void)?
    var modalDidClose: (() -> Void)?

    private let desktopURL: URL
    private let storageURL: URL
    private let fileManager = FileManager.default
    private let storageService: ScreenshotStorageService
    private let importService: ScreenshotImportService
    private let favoritesStore: ScreenshotFavoritesStore
    private let trashService: ScreenshotTrashService
    private var selectionService = ScreenshotSelectionService()
    private var desktopMonitor: DirectoryMonitor?
    private var storageMonitor: DirectoryMonitor?
    private var subfolderMonitors: [URL: DirectoryMonitor] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var pendingTrashedScreenshots: [PendingTrashedScreenshot] = []
    private var trashUndoDismissTask: Task<Void, Never>?
    private var isRunning = false
    private var pendingSelectionURLs: [URL]?
    private static let presentationModeDefaultsKey = "screenshoss.presentationMode"

    init(
        desktopURL: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0],
        storageURL customStorageURL: URL? = nil,
        favoritesURL customFavoritesURL: URL? = nil,
        trashService customTrashService: ScreenshotTrashService? = nil
    ) {
        self.desktopURL = desktopURL
        if let storedMode = UserDefaults.standard.string(forKey: Self.presentationModeDefaultsKey),
           let storedPresentationMode = ShelfPresentationMode(rawValue: storedMode) {
            presentationMode = storedPresentationMode
        } else {
            presentationMode = .top
        }
        let resolvedStorageURL: URL
        let resolvedFavoritesURL: URL
        if let customStorageURL {
            resolvedStorageURL = customStorageURL
            resolvedFavoritesURL = customFavoritesURL
                ?? customStorageURL.deletingLastPathComponent().appendingPathComponent("favorites.json")
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let supportURL = appSupport.appendingPathComponent("Screenshoss", isDirectory: true)
            let legacyURL = appSupport.appendingPathComponent("Shoss", isDirectory: true)
            ScreenshotStorageService.migrateLegacyFolderIfNeeded(
                legacyURL: legacyURL,
                currentURL: supportURL
            )
            resolvedStorageURL = supportURL.appendingPathComponent("Screenshots", isDirectory: true)
            resolvedFavoritesURL = customFavoritesURL
                ?? supportURL.appendingPathComponent("favorites.json")
        }

        storageURL = resolvedStorageURL
        storageService = ScreenshotStorageService(storageURL: resolvedStorageURL)
        importService = ScreenshotImportService(
            desktopURL: desktopURL,
            storageURL: resolvedStorageURL
        )
        favoritesStore = ScreenshotFavoritesStore(fileURL: resolvedFavoritesURL)
        trashService = customTrashService ?? ScreenshotTrashService()
    }

    var filteredItems: [ScreenshotItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let scopedItems = if showingFavoritesOnly {
            items.filter(\.isFavorite)
        } else if let selectedFolderName {
            items.filter { $0.folderName == selectedFolderName }
        } else {
            items.filter { $0.folderName == nil }
        }

        guard !query.isEmpty else { return scopedItems }
        return scopedItems.filter { $0.name.lowercased().contains(query) }
    }

    var desktopPath: String {
        storageURL.path
    }

    var favoriteCount: Int {
        items.filter(\.isFavorite).count
    }

    var selectedItemCount: Int {
        selectedItemsInDisplayOrder().count
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        do {
            try storageService.ensureDirectory()
        } catch {
            runErrorAlert(error)
            return
        }
        refresh()
        desktopMonitor = DirectoryMonitor(directoryURL: desktopURL) { [weak self] in
            Task { @MainActor in
                self?.scheduleRefresh()
            }
        }
        desktopMonitor?.start()
        storageMonitor = DirectoryMonitor(directoryURL: storageURL) { [weak self] in
            Task { @MainActor in
                self?.scheduleRefresh()
            }
        }
        storageMonitor?.start()
    }

    func refresh() {
        scheduleRefresh(delayMilliseconds: 0)
    }

    func select(_ item: ScreenshotItem, extendingSelection: Bool = false, togglingSelection: Bool = false) {
        if extendingSelection {
            selectionService.selectRange(through: item, in: filteredItems)
        } else if togglingSelection {
            selectionService.toggle(item, in: filteredItems)
        } else {
            setSingleSelection(item)
        }
        publishSelection()
        isExpanded = true
    }

    func isSelected(_ item: ScreenshotItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func selectFolder(_ folderName: String?) {
        showingFavoritesOnly = false
        selectedFolderName = folderName
        setSingleSelection(filteredItems.first)
    }

    func toggleFavoritesFilter() {
        showingFavoritesOnly.toggle()
        setSingleSelection(filteredItems.first)
    }

    func toggleFavorite(_ item: ScreenshotItem) {
        guard let relativePath = relativePath(for: item.url) else { return }
        do {
            try favoritesStore.toggle(relativePath)
            refresh()
        } catch {
            runErrorAlert(error)
        }
    }

    @discardableResult
    func copy(_ item: ScreenshotItem) -> Bool {
        guard let image = NSImage(contentsOf: item.url) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else { return false }
        return true
    }

    @discardableResult
    func copySelection() -> Bool {
        let selectedItems = selectedItemsInDisplayOrder()
        guard !selectedItems.isEmpty else { return false }

        if selectedItems.count == 1, let item = selectedItems.first {
            return copy(item)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(selectedItems.map { $0.url as NSURL })
    }

    func open(_ item: ScreenshotItem) {
        NSApp.activate(ignoringOtherApps: false)
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ScreenshotItem) {
        NSApp.activate(ignoringOtherApps: false)
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func delete(_ item: ScreenshotItem) {
        deleteItems([item])
    }

    @discardableResult
    func deleteSelection(fallback item: ScreenshotItem? = nil) -> Bool {
        let selectedItems = selectedItemsInDisplayOrder()
        let itemsToDelete: [ScreenshotItem]
        if let item, !selectedItemIDs.contains(item.id) {
            itemsToDelete = [item]
        } else if !selectedItems.isEmpty {
            itemsToDelete = selectedItems
        } else if let item {
            itemsToDelete = [item]
        } else {
            itemsToDelete = []
        }

        return deleteItems(itemsToDelete)
    }

    func shouldActOnSelection(for item: ScreenshotItem) -> Bool {
        selectedItemIDs.contains(item.id) && selectedItemCount > 1
    }

    @discardableResult
    private func deleteItems(_ itemsToDelete: [ScreenshotItem]) -> Bool {
        let uniqueItems = Array(Dictionary(grouping: itemsToDelete, by: \.id).compactMap { $0.value.first })
        guard !uniqueItems.isEmpty else { return false }

        var deletedIDs: Set<URL> = []
        var trashedScreenshots: [PendingTrashedScreenshot] = []
        do {
            for item in uniqueItems {
                let location = try trashService.moveToTrash(item.url)
                trashedScreenshots.append(
                    PendingTrashedScreenshot(location: location, wasFavorite: item.isFavorite)
                )
                removeFavoritePath(for: item.url)
                deletedIDs.insert(item.id)
            }

            applyOptimisticDeletion(ids: deletedIDs)
            presentTrashUndo(for: trashedScreenshots)
            refresh()
            return true
        } catch {
            if !deletedIDs.isEmpty {
                applyOptimisticDeletion(ids: deletedIDs)
                presentTrashUndo(for: trashedScreenshots)
                refresh()
            }
            runErrorAlert(error)
            return !deletedIDs.isEmpty
        }
    }

    private func applyOptimisticDeletion(ids deletedIDs: Set<URL>) {
        let previousSelectedURL = selectedItem?.url
        items.removeAll { deletedIDs.contains($0.id) }
        folders = folders.map { folder in
            ScreenshotFolder(
                name: folder.name,
                url: folder.url,
                count: items.lazy.filter { $0.folderName == folder.name }.count
            )
        }

        selectionService.remove(ids: deletedIDs)
        selectionService.reconcile(
            previousSelectedURL: previousSelectedURL.flatMap {
                deletedIDs.contains($0) ? nil : $0
            },
            allItems: items,
            visibleItems: filteredItems
        )
        publishSelection()
    }

    func undoLastTrash() {
        guard !pendingTrashedScreenshots.isEmpty else { return }

        trashUndoDismissTask?.cancel()
        let screenshotsToRestore = pendingTrashedScreenshots
        pendingTrashedScreenshots = []
        trashUndoNotice = nil

        var restoredURLs: [URL] = []
        var firstError: Error?
        for screenshot in screenshotsToRestore {
            do {
                let restoredURL = try trashService.restore(screenshot.location)
                restoredURLs.append(restoredURL)
                if screenshot.wasFavorite, let restoredPath = relativePath(for: restoredURL) {
                    try favoritesStore.add(restoredPath)
                }
            } catch {
                firstError = firstError ?? error
            }
        }

        if !restoredURLs.isEmpty {
            pendingSelectionURLs = restoredURLs
            refresh()
        }
        if let firstError {
            runErrorAlert(firstError)
        }
    }

    private func presentTrashUndo(for screenshots: [PendingTrashedScreenshot]) {
        guard !screenshots.isEmpty else { return }

        trashUndoDismissTask?.cancel()
        pendingTrashedScreenshots.append(contentsOf: screenshots)
        trashUndoNotice = TrashUndoNotice(itemCount: pendingTrashedScreenshots.count)
        trashUndoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.pendingTrashedScreenshots = []
            self?.trashUndoNotice = nil
        }
    }

    func createFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Name this screenshot folder."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = "Project"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = runModalAlert(alert)
        guard response == .alertFirstButtonReturn else { return }

        let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeFolderName(folderName) else {
            showFolderAlert(message: "Use a simple folder name.", info: "Folder names cannot contain path separators, dot segments, or hidden-file prefixes.")
            return
        }

        let folderURL = storageURL.appendingPathComponent(folderName, isDirectory: true)
        guard !fileManager.fileExists(atPath: folderURL.path) else {
            showFolderAlert(message: "A folder with that name already exists.", info: nil)
            return
        }

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
            refresh()
            selectFolder(folderName)
        } catch {
            runErrorAlert(error)
        }
    }

    func renameFolder(_ folder: ScreenshotFolder) {
        let alert = NSAlert()
        alert.messageText = "Rename Folder"
        alert.informativeText = "Enter a new folder name."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = folder.name
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = runModalAlert(alert)
        guard response == .alertFirstButtonReturn else { return }

        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName != folder.name else { return }
        guard Self.isSafeFolderName(newName) else {
            showFolderAlert(message: "Use a simple folder name.", info: "Folder names cannot contain path separators, dot segments, or hidden-file prefixes.")
            return
        }

        let newURL = storageURL.appendingPathComponent(newName, isDirectory: true)
        guard !fileManager.fileExists(atPath: newURL.path) else {
            showFolderAlert(message: "A folder with that name already exists.", info: nil)
            return
        }

        do {
            try fileManager.moveItem(at: folder.url, to: newURL)
            updateFavoriteFolderPrefix(from: folder.name, to: newName)
            if selectedFolderName == folder.name {
                selectedFolderName = newName
            }
            refresh()
        } catch {
            runErrorAlert(error)
        }
    }

    func deleteFolder(_ folder: ScreenshotFolder) {
        let alert = NSAlert()
        alert.messageText = "Delete \(folder.name)?"
        alert.informativeText = folder.count == 0
            ? "This folder will be moved to Trash."
            : "This folder and \(folder.count) screenshot\(folder.count == 1 ? "" : "s") inside it will be moved to Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = runModalAlert(alert)
        guard response == .alertFirstButtonReturn else { return }

        do {
            try fileManager.trashItem(at: folder.url, resultingItemURL: nil)
            removeFavoriteFolderPrefix(folder.name)
            if selectedFolderName == folder.name {
                selectedFolderName = nil
            }
            selectionService.removeItems(inFolder: folder.name, from: items)
            publishSelection()
            refresh()
        } catch {
            runErrorAlert(error)
        }
    }

    func beginDragging(_ item: ScreenshotItem) {
        if selectedItemIDs.contains(item.id), selectedItemIDs.count > 1 {
            draggedItemURLs = selectedItemIDs
        } else {
            setSingleSelection(item)
            draggedItemURLs = [item.id]
        }
    }

    func dragURLs(startingFrom item: ScreenshotItem) -> [URL] {
        beginDragging(item)
        let draggedURLs = draggedItemURLs
        let orderedURLs = filteredItems.map(\.url).filter { draggedURLs.contains($0) }
        return orderedURLs.isEmpty ? [item.url] : orderedURLs
    }

    func finishDragging(shouldCollapse: Bool) {
        draggedItemURLs = []
        if shouldCollapse {
            isExpanded = false
        }
    }

    @discardableResult
    func moveDraggedItem(toFolder folderName: String?) -> Bool {
        let draggedURLs = draggedItemURLs
        draggedItemURLs = []
        let draggedItems = draggedURLs.compactMap { url in
            items.first(where: { $0.url == url })
        }
        return move(draggedItems, toFolder: folderName)
    }

    @discardableResult
    func move(_ item: ScreenshotItem, toFolder folderName: String?) -> Bool {
        move([item], toFolder: folderName)
    }

    @discardableResult
    private func move(_ movingItems: [ScreenshotItem], toFolder folderName: String?) -> Bool {
        guard !movingItems.isEmpty else { return false }

        let destinationDirectory: URL
        if let folderName {
            guard let folder = folders.first(where: { $0.name == folderName }) else { return false }
            destinationDirectory = folder.url
        } else {
            destinationDirectory = storageURL
        }

        let movableItems = movingItems.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL != destinationDirectory.standardizedFileURL
        }
        guard !movableItems.isEmpty else { return false }

        var movedURLs: [URL] = []
        do {
            for item in movableItems {
                let destinationURL = storageService.uniqueDestinationURL(
                    for: item.name,
                    in: destinationDirectory
                )
                try fileManager.moveItem(at: item.url, to: destinationURL)
                updateFavoritePath(from: item.url, to: destinationURL)
                movedURLs.append(destinationURL)
            }
            pendingSelectionURLs = movedURLs
            refresh()
            return true
        } catch {
            if !movedURLs.isEmpty {
                pendingSelectionURLs = movedURLs
            }
            refresh()
            runErrorAlert(error)
            return !movedURLs.isEmpty
        }
    }

    func rename(_ item: ScreenshotItem) {
        let alert = NSAlert()
        alert.messageText = "Rename Screenshot"
        alert.informativeText = "Enter a new name for this screenshot."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = item.name
        textField.placeholderString = "filename.png"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = runModalAlert(alert)
        guard response == .alertFirstButtonReturn else { return }

        let newName = normalizedRename(
            textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            originalName: item.name
        )
        guard !newName.isEmpty, newName != item.name else { return }
        guard Self.isSafeScreenshotFilename(newName) else {
            let invalidAlert = NSAlert()
            invalidAlert.messageText = "Use a simple filename."
            invalidAlert.informativeText = "Screenshot names cannot contain folders, path separators, or unsupported image extensions."
            invalidAlert.alertStyle = .warning
            invalidAlert.addButton(withTitle: "OK")
            runModalAlert(invalidAlert)
            return
        }

        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !fileManager.fileExists(atPath: newURL.path) else {
            let dupAlert = NSAlert()
            dupAlert.messageText = "A file with that name already exists."
            dupAlert.alertStyle = .warning
            dupAlert.addButton(withTitle: "OK")
            runModalAlert(dupAlert)
            return
        }

        do {
            try fileManager.moveItem(at: item.url, to: newURL)
            updateFavoritePath(from: item.url, to: newURL)
            pendingSelectionURLs = [newURL]
            refresh()
        } catch {
            runErrorAlert(error)
        }
    }

    func openStorageFolder() {
        NSWorkspace.shared.open(storageURL)
    }

    func count(forFolder folderName: String?) -> Int {
        if let folderName {
            return items.filter { $0.folderName == folderName }.count
        }
        return items.filter { $0.folderName == nil }.count
    }

    private func relativePath(for url: URL) -> String? {
        ScreenshotItem.relativePath(for: url, storageRootURL: storageURL)
    }

    private func updateFavoritePath(from oldURL: URL, to newURL: URL) {
        guard let oldPath = relativePath(for: oldURL),
              let newPath = relativePath(for: newURL) else {
            return
        }

        do {
            try favoritesStore.updatePath(from: oldPath, to: newPath)
        } catch {
            runErrorAlert(error)
        }
    }

    private func removeFavoritePath(for url: URL) {
        guard let relativePath = relativePath(for: url) else { return }
        do {
            try favoritesStore.remove(relativePath)
        } catch {
            runErrorAlert(error)
        }
    }

    private func updateFavoriteFolderPrefix(from oldName: String, to newName: String) {
        do {
            try favoritesStore.updateFolderPrefix(from: oldName, to: newName)
        } catch {
            runErrorAlert(error)
        }
    }

    private func removeFavoriteFolderPrefix(_ folderName: String) {
        do {
            try favoritesStore.removeFolderPrefix(folderName)
        } catch {
            runErrorAlert(error)
        }
    }

    private func setSingleSelection(_ item: ScreenshotItem?) {
        selectionService.setSingle(item)
        publishSelection()
    }

    private func selectedItemsInDisplayOrder() -> [ScreenshotItem] {
        selectionService.selectedItems(in: filteredItems)
    }

    private func publishSelection() {
        selectedItem = selectionService.selectedItem
        selectedItemIDs = selectionService.selectedIDs
    }

    func setPresentationMode(_ mode: ShelfPresentationMode) {
        presentationMode = mode
    }

    func cyclePresentationMode() {
        switch presentationMode {
        case .top:
            presentationMode = .left
        case .left:
            presentationMode = .right
        case .right:
            presentationMode = .top
        }
    }


    nonisolated static func isSafeScreenshotFilename(_ filename: String) -> Bool {
        guard filename != ".", filename != ".." else { return false }
        guard filename.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else { return false }
        let url = URL(fileURLWithPath: filename)
        guard url.lastPathComponent == filename else { return false }
        return ScreenshotItem.isSupportedImageFile(url)
    }

    nonisolated static func isSafeFolderName(_ folderName: String) -> Bool {
        guard !folderName.isEmpty, folderName != ".", folderName != ".." else { return false }
        guard !folderName.hasPrefix(".") else { return false }
        guard folderName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else { return false }
        return URL(fileURLWithPath: folderName).lastPathComponent == folderName
    }

    nonisolated static func isSafeFavoriteRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        guard path.rangeOfCharacter(from: CharacterSet(charactersIn: ":")) == nil else { return false }

        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 1 || parts.count == 2 else { return false }
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else {
            return false
        }

        if parts.count == 2, !isSafeFolderName(parts[0]) {
            return false
        }

        return isSafeScreenshotFilename(parts.last ?? "")
    }

    private func normalizedRename(_ filename: String, originalName: String) -> String {
        guard !filename.isEmpty else { return filename }
        guard (filename as NSString).pathExtension.isEmpty else { return filename }

        let originalExtension = (originalName as NSString).pathExtension
        guard !originalExtension.isEmpty else { return filename }
        return "\(filename).\(originalExtension)"
    }

    private func scheduleRefresh(retryCount: Int = 0, delayMilliseconds: Int = 2_000) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let favoritePaths = favoritesStore.relativePaths

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            }
            guard !Task.isCancelled else { return }

            let pending = await importService.importScreenshots()
            guard !Task.isCancelled else { return }
            let snapshot = await storageService.scan(favoriteRelativePaths: favoritePaths)
            guard !Task.isCancelled, generation == refreshGeneration else { return }

            apply(snapshot)
            if pending, retryCount < 10 {
                scheduleRefresh(retryCount: retryCount + 1)
            }
        }
    }

    private func apply(_ snapshot: ScreenshotStorageSnapshot) {
        let previousSelectedURL = selectedItem?.url
        items = snapshot.items
        folders = snapshot.folders

        if let selectedFolderName, !folders.contains(where: { $0.name == selectedFolderName }) {
            self.selectedFolderName = nil
        }

        if let pendingSelectionURLs {
            selectionService.restoreAfterMove(
                to: pendingSelectionURLs,
                visibleItems: filteredItems
            )
            self.pendingSelectionURLs = nil
        } else {
            selectionService.reconcile(
                previousSelectedURL: previousSelectedURL,
                allItems: items,
                visibleItems: filteredItems
            )
        }
        publishSelection()
        updateSubfolderMonitors()
    }

    private func updateSubfolderMonitors() {
        let currentURLs = Set(folders.map { $0.url.standardizedFileURL })
        let removedURLs = subfolderMonitors.keys.filter { !currentURLs.contains($0) }

        for url in removedURLs {
            subfolderMonitors[url]?.stop()
            subfolderMonitors.removeValue(forKey: url)
        }

        for url in currentURLs where subfolderMonitors[url] == nil {
            let monitor = DirectoryMonitor(directoryURL: url) { [weak self] in
                Task { @MainActor in
                    self?.scheduleRefresh()
                }
            }
            subfolderMonitors[url] = monitor
            monitor.start()
        }
    }

    func refreshAndWaitForTesting() async {
        refreshTask?.cancel()
        refreshGeneration += 1
        let pending = await importService.importScreenshots()
        let snapshot = await storageService.scan(
            favoriteRelativePaths: favoritesStore.relativePaths
        )
        apply(snapshot)
        if pending {
            scheduleRefresh()
        }
    }

    private func showFolderAlert(message: String, info: String?) {
        let alert = NSAlert()
        alert.messageText = message
        if let info {
            alert.informativeText = info
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        runModalAlert(alert)
    }

    @discardableResult
    private func runModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        modalWillOpen?()
        defer { modalDidClose?() }
        alert.window.level = .modalPanel
        return alert.runModal()
    }

    private func runErrorAlert(_ error: Error) {
        runModalAlert(NSAlert(error: error))
    }
}

final class DirectoryMonitor {
    private let directoryURL: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "screenshoss.desktop.monitor", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard source == nil else { return }

        descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.onChange()
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }
}
