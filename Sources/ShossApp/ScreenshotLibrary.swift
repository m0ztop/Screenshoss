import AppKit
import Combine
import Foundation

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
    @Published var isExpanded = false {
        didSet {
            guard oldValue != isExpanded else { return }
            expansionDidChange?(isExpanded)
        }
    }

    var expansionDidChange: ((Bool) -> Void)?
    var closeAction: (() -> Void)?
    var modalWillOpen: (() -> Void)?
    var modalDidClose: (() -> Void)?

    private let desktopURL: URL
    private let storageURL: URL
    private let favoritesURL: URL
    private let fileManager = FileManager.default
    private var favoriteRelativePaths: Set<String> = []
    private var desktopMonitor: DirectoryMonitor?
    private var storageMonitor: DirectoryMonitor?
    private var refreshTask: Task<Void, Never>?
    private var isRunning = false
    private var selectionAnchorID: URL?

    init(desktopURL: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]) {
        self.desktopURL = desktopURL
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let screenshossSupportURL = appSupport.appendingPathComponent("Screenshoss", isDirectory: true)
        let legacySupportURL = appSupport.appendingPathComponent("Shoss", isDirectory: true)
        Self.migrateLegacySupportFolderIfNeeded(
            fileManager: fileManager,
            legacyURL: legacySupportURL,
            currentURL: screenshossSupportURL
        )
        storageURL = screenshossSupportURL.appendingPathComponent("Screenshots", isDirectory: true)
        favoritesURL = screenshossSupportURL.appendingPathComponent("favorites.json")
        loadFavoritePaths()
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
        ensureStorageDirectory()
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
        let pending = importScreenshotsFromDesktop()
        scanStorage()
        if pending {
            scheduleRefresh()
        }
    }

    func select(_ item: ScreenshotItem, extendingSelection: Bool = false, togglingSelection: Bool = false) {
        if extendingSelection {
            selectRange(through: item)
            selectedItem = item
        } else if togglingSelection {
            toggleSelection(of: item)
        } else {
            setSingleSelection(item)
        }
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
        if favoriteRelativePaths.contains(relativePath) {
            favoriteRelativePaths.remove(relativePath)
        } else {
            favoriteRelativePaths.insert(relativePath)
        }
        saveFavoritePaths()
        scanStorage()
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
        do {
            for item in uniqueItems {
                try fileManager.trashItem(at: item.url, resultingItemURL: nil)
                removeFavoritePath(for: item.url)
                deletedIDs.insert(item.id)
            }

            selectedItemIDs.subtract(deletedIDs)
            if let selectedItem, deletedIDs.contains(selectedItem.id) {
                self.selectedItem = nil
            }
            refresh()
            return true
        } catch {
            if !deletedIDs.isEmpty {
                selectedItemIDs.subtract(deletedIDs)
                if let selectedItem, deletedIDs.contains(selectedItem.id) {
                    self.selectedItem = nil
                }
                refresh()
            }
            runErrorAlert(error)
            return !deletedIDs.isEmpty
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
            if let selectedItem, selectedItem.folderName == folder.name {
                self.selectedItem = nil
            }
            selectedItemIDs = selectedItemIDs.filter { id in
                items.first(where: { $0.id == id })?.folderName != folder.name
            }
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
                let destinationURL = uniqueDestinationURL(for: item.name, in: destinationDirectory)
                try fileManager.moveItem(at: item.url, to: destinationURL)
                updateFavoritePath(from: item.url, to: destinationURL)
                movedURLs.append(destinationURL)
            }
            refresh()
            restoreSelection(afterMovingTo: movedURLs)
            return true
        } catch {
            runErrorAlert(error)
            return false
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
            refresh()
            if let renamedItem = items.first(where: { $0.url == newURL }) {
                setSingleSelection(renamedItem)
            }
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

    private func loadFavoritePaths() {
        guard let data = try? Data(contentsOf: favoritesURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            favoriteRelativePaths = []
            return
        }
        favoriteRelativePaths = Set(paths.filter(Self.isSafeFavoriteRelativePath))
    }

    private func saveFavoritePaths() {
        do {
            try fileManager.createDirectory(
                at: favoritesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(favoriteRelativePaths.sorted())
            try data.write(to: favoritesURL, options: [.atomic])
        } catch {
            runErrorAlert(error)
        }
    }

    private func relativePath(for url: URL) -> String? {
        ScreenshotItem.relativePath(for: url, storageRootURL: storageURL)
    }

    private func updateFavoritePath(from oldURL: URL, to newURL: URL) {
        guard let oldPath = relativePath(for: oldURL),
              favoriteRelativePaths.contains(oldPath),
              let newPath = relativePath(for: newURL) else {
            return
        }

        favoriteRelativePaths.remove(oldPath)
        favoriteRelativePaths.insert(newPath)
        saveFavoritePaths()
    }

    private func removeFavoritePath(for url: URL) {
        guard let relativePath = relativePath(for: url),
              favoriteRelativePaths.remove(relativePath) != nil else {
            return
        }
        saveFavoritePaths()
    }

    private func updateFavoriteFolderPrefix(from oldName: String, to newName: String) {
        let oldPrefix = oldName + "/"
        let movedPaths = favoriteRelativePaths.filter { $0.hasPrefix(oldPrefix) }
        guard !movedPaths.isEmpty else { return }

        for path in movedPaths {
            favoriteRelativePaths.remove(path)
            favoriteRelativePaths.insert(newName + "/" + String(path.dropFirst(oldPrefix.count)))
        }
        saveFavoritePaths()
    }

    private func removeFavoriteFolderPrefix(_ folderName: String) {
        let prefix = folderName + "/"
        let beforeCount = favoriteRelativePaths.count
        favoriteRelativePaths = favoriteRelativePaths.filter { !$0.hasPrefix(prefix) }
        guard favoriteRelativePaths.count != beforeCount else { return }
        saveFavoritePaths()
    }

    private func ensureStorageDirectory() {
        let dir = storageURL
        guard !fileManager.fileExists(atPath: dir.path) else { return }
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func setSingleSelection(_ item: ScreenshotItem?) {
        selectedItem = item
        if let item {
            selectedItemIDs = [item.id]
            selectionAnchorID = item.id
        } else {
            selectedItemIDs = []
            selectionAnchorID = nil
        }
    }

    private func selectRange(through item: ScreenshotItem) {
        guard let anchorID = selectionAnchorID,
              let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchorID }),
              let itemIndex = filteredItems.firstIndex(where: { $0.id == item.id }) else {
            setSingleSelection(item)
            return
        }

        let bounds = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
        selectedItemIDs = Set(filteredItems[bounds].map(\.id))
    }

    private func toggleSelection(of item: ScreenshotItem) {
        if selectedItemIDs.contains(item.id), selectedItemIDs.count > 1 {
            selectedItemIDs.remove(item.id)
            if selectedItem == item {
                selectedItem = filteredItems.first { selectedItemIDs.contains($0.id) }
                selectionAnchorID = selectedItem?.id
            }
        } else {
            selectedItemIDs.insert(item.id)
            selectedItem = item
            selectionAnchorID = item.id
        }
    }

    private func selectedItemsInDisplayOrder() -> [ScreenshotItem] {
        let selectedIDs = selectedItemIDs
        let orderedItems = filteredItems.filter { selectedIDs.contains($0.id) }
        if !orderedItems.isEmpty {
            return orderedItems
        }

        return selectedItem.map { [$0] } ?? []
    }

    private func restoreSelection(afterMovingTo movedURLs: [URL]) {
        let movedURLSet = Set(movedURLs)
        let visibleMovedItems = filteredItems.filter { movedURLSet.contains($0.url) }
        if !visibleMovedItems.isEmpty {
            selectedItemIDs = Set(visibleMovedItems.map(\.id))
            selectedItem = visibleMovedItems.first
            selectionAnchorID = selectedItem?.id
            return
        }

        setSingleSelection(filteredItems.first)
    }

    private static func migrateLegacySupportFolderIfNeeded(
        fileManager: FileManager,
        legacyURL: URL,
        currentURL: URL
    ) {
        guard legacyURL.standardizedFileURL != currentURL.standardizedFileURL else { return }
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        guard !fileManager.fileExists(atPath: currentURL.path) else { return }
        try? fileManager.moveItem(at: legacyURL, to: currentURL)
    }

    @discardableResult
    private func importScreenshotsFromDesktop() -> Bool {
        guard let desktopFiles = try? fileManager.contentsOfDirectory(
            at: desktopURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        let screenshots = desktopFiles.filter(ScreenshotItem.looksLikeMacScreenshot)
        var hasPending = false

        for sourceURL in screenshots {
            guard isStableFile(at: sourceURL) else {
                hasPending = true
                continue
            }

            let filename = sourceURL.lastPathComponent
            let destinationURL = uniqueDestinationURL(for: filename, in: storageURL)

            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                hasPending = true
                continue
            }
        }

        return hasPending
    }

    private func isStableFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modDate = values.contentModificationDate else {
            return false
        }
        return Date().timeIntervalSince(modDate) > 2.0
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

    private func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }

        return candidate
    }

    private func scanStorage() {
        let selectedURL = selectedItem?.url
        let rootURLs = (try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let subfolderURLs = rootURLs.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        let nestedURLs = subfolderURLs.flatMap { folderURL in
            (try? fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        let nextItems = (rootURLs + nestedURLs)
            .filter(ScreenshotItem.isSupportedImageFile)
            .compactMap {
                ScreenshotItem.make(
                    url: $0,
                    storageRootURL: storageURL,
                    favoriteRelativePaths: favoriteRelativePaths
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        items = nextItems
        folders = subfolderURLs
            .map { folderURL in
                ScreenshotFolder(
                    name: folderURL.lastPathComponent,
                    url: folderURL,
                    count: nextItems.filter { $0.folderName == folderURL.lastPathComponent }.count
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if let selectedFolderName, !folders.contains(where: { $0.name == selectedFolderName }) {
            self.selectedFolderName = nil
        }

        if items.isEmpty {
            setSingleSelection(nil)
            return
        }

        let visibleIDs = Set(filteredItems.map(\.id))
        selectedItemIDs.formIntersection(visibleIDs)

        if let selectedURL,
           let updatedSelection = filteredItems.first(where: { $0.url == selectedURL }) {
            selectedItem = updatedSelection
            if selectedItemIDs.isEmpty {
                selectedItemIDs = [updatedSelection.id]
                selectionAnchorID = updatedSelection.id
            }
            return
        }

        if let selectedItem, filteredItems.contains(selectedItem) {
            if selectedItemIDs.isEmpty {
                selectedItemIDs = [selectedItem.id]
                selectionAnchorID = selectedItem.id
            }
            return
        }

        setSingleSelection(filteredItems.first)
    }

    private func scheduleRefresh(retryCount: Int = 0) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2000))
            guard !Task.isCancelled else { return }
            let pending = importScreenshotsFromDesktop()
            scanStorage()
            if pending, retryCount < 10 {
                scheduleRefresh(retryCount: retryCount + 1)
            }
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
