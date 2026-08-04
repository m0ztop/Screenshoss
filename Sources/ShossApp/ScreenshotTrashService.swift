import Foundation

struct TrashedScreenshotLocation: Equatable {
    let originalURL: URL
    let trashURL: URL
}

struct ScreenshotTrashService {
    private let fileManager: FileManager
    private let trashDirectoryURL: URL?

    init(
        fileManager: FileManager = .default,
        trashDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.trashDirectoryURL = trashDirectoryURL
    }

    func moveToTrash(_ originalURL: URL) throws -> TrashedScreenshotLocation {
        if let trashDirectoryURL {
            try fileManager.createDirectory(at: trashDirectoryURL, withIntermediateDirectories: true)
            let destinationURL = ScreenshotStorageService.uniqueDestinationURL(
                for: originalURL.lastPathComponent,
                in: trashDirectoryURL,
                fileManager: fileManager
            )
            try fileManager.moveItem(at: originalURL, to: destinationURL)
            return TrashedScreenshotLocation(originalURL: originalURL, trashURL: destinationURL)
        }

        var resultingURL: NSURL?
        try fileManager.trashItem(at: originalURL, resultingItemURL: &resultingURL)
        guard let resultingURL else {
            throw ScreenshotTrashError.missingTrashLocation
        }
        return TrashedScreenshotLocation(
            originalURL: originalURL,
            trashURL: resultingURL as URL
        )
    }

    func restore(_ location: TrashedScreenshotLocation) throws -> URL {
        let parentURL = location.originalURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let destinationURL = ScreenshotStorageService.uniqueDestinationURL(
            for: location.originalURL.lastPathComponent,
            in: parentURL,
            fileManager: fileManager
        )
        try fileManager.moveItem(at: location.trashURL, to: destinationURL)
        return destinationURL
    }
}

private enum ScreenshotTrashError: LocalizedError {
    case missingTrashLocation

    var errorDescription: String? {
        "The screenshot was moved to Trash, but macOS did not return its new location."
    }
}
