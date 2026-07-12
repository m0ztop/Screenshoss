import Foundation

final class ScreenshotFavoritesStore {
    private let fileURL: URL
    private(set) var relativePaths: Set<String>

    init(fileURL: URL) {
        self.fileURL = fileURL
        relativePaths = Self.load(from: fileURL)
    }

    func toggle(_ relativePath: String) throws {
        if relativePaths.contains(relativePath) {
            relativePaths.remove(relativePath)
        } else {
            relativePaths.insert(relativePath)
        }
        try save()
    }

    func updatePath(from oldPath: String, to newPath: String) throws {
        guard relativePaths.remove(oldPath) != nil else { return }
        relativePaths.insert(newPath)
        try save()
    }

    func remove(_ relativePath: String) throws {
        guard relativePaths.remove(relativePath) != nil else { return }
        try save()
    }

    func updateFolderPrefix(from oldName: String, to newName: String) throws {
        let oldPrefix = oldName + "/"
        let movedPaths = relativePaths.filter { $0.hasPrefix(oldPrefix) }
        guard !movedPaths.isEmpty else { return }

        for path in movedPaths {
            relativePaths.remove(path)
            relativePaths.insert(newName + "/" + String(path.dropFirst(oldPrefix.count)))
        }
        try save()
    }

    func removeFolderPrefix(_ folderName: String) throws {
        let prefix = folderName + "/"
        let nextPaths = relativePaths.filter { !$0.hasPrefix(prefix) }
        guard nextPaths.count != relativePaths.count else { return }
        relativePaths = nextPaths
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(relativePaths.sorted())
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from fileURL: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(paths.filter(ScreenshotLibrary.isSafeFavoriteRelativePath))
    }
}
