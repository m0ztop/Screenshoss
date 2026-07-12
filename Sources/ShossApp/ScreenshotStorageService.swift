import Foundation

struct ScreenshotStorageSnapshot: Sendable {
    let items: [ScreenshotItem]
    let folders: [ScreenshotFolder]
}

struct ScreenshotStorageService: Sendable {
    let storageURL: URL

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    func scan(favoriteRelativePaths: Set<String>) async -> ScreenshotStorageSnapshot {
        let storageURL = storageURL
        return await Task.detached(priority: .utility) {
            Self.scanSynchronously(
                storageURL: storageURL,
                favoriteRelativePaths: favoriteRelativePaths
            )
        }.value
    }

    func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        Self.uniqueDestinationURL(
            for: filename,
            in: directory,
            fileManager: .default
        )
    }

    static func migrateLegacyFolderIfNeeded(legacyURL: URL, currentURL: URL) {
        let fileManager = FileManager.default
        guard legacyURL.standardizedFileURL != currentURL.standardizedFileURL else { return }
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        guard !fileManager.fileExists(atPath: currentURL.path) else { return }
        try? fileManager.moveItem(at: legacyURL, to: currentURL)
    }

    static func uniqueDestinationURL(
        for filename: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty
                ? "\(baseName) (\(counter))"
                : "\(baseName) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }

        return candidate
    }

    private static func scanSynchronously(
        storageURL: URL,
        favoriteRelativePaths: Set<String>
    ) -> ScreenshotStorageSnapshot {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]
        let rootURLs = (try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let subfolderURLs = rootURLs.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                return false
            }
            return values.isDirectory == true && values.isSymbolicLink != true
        }

        let nestedURLs = subfolderURLs.flatMap { folderURL in
            (try? fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        let items = (rootURLs + nestedURLs)
            .filter(ScreenshotItem.isSupportedImageFile)
            .compactMap {
                ScreenshotItem.make(
                    url: $0,
                    storageRootURL: storageURL,
                    favoriteRelativePaths: favoriteRelativePaths
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        let folders = subfolderURLs
            .map { folderURL in
                ScreenshotFolder(
                    name: folderURL.lastPathComponent,
                    url: folderURL,
                    count: items.lazy.filter { $0.folderName == folderURL.lastPathComponent }.count
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return ScreenshotStorageSnapshot(items: items, folders: folders)
    }
}
