import Foundation
import ImageIO

struct ScreenshotImportResult: Equatable, Sendable {
    let hasPendingFiles: Bool
    let importedCount: Int
}

struct ScreenshotImportService: Sendable {
    let desktopURL: URL
    let storageURL: URL
    var stableFileAge: TimeInterval = 0
    var stabilityCheckMilliseconds = 150

    func importScreenshots() async -> ScreenshotImportResult {
        let desktopURL = desktopURL
        let storageURL = storageURL
        let stableFileAge = stableFileAge
        let stabilityCheckMilliseconds = stabilityCheckMilliseconds

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let desktopFiles = try? fileManager.contentsOfDirectory(
                at: desktopURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles]
            ) else {
                return ScreenshotImportResult(hasPendingFiles: false, importedCount: 0)
            }

            let screenshots = desktopFiles.filter(ScreenshotItem.looksLikeMacScreenshot)
            var hasPending = false
            var importedCount = 0

            for sourceURL in screenshots {
                guard await Self.isStableFile(
                    at: sourceURL,
                    minimumAge: stableFileAge,
                    checkMilliseconds: stabilityCheckMilliseconds,
                    fileManager: fileManager
                ) else {
                    hasPending = true
                    continue
                }

                let destinationURL = ScreenshotStorageService.uniqueDestinationURL(
                    for: sourceURL.lastPathComponent,
                    in: storageURL,
                    fileManager: fileManager
                )

                do {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                    importedCount += 1
                } catch {
                    hasPending = true
                }
            }

            return ScreenshotImportResult(
                hasPendingFiles: hasPending,
                importedCount: importedCount
            )
        }.value
    }

    private struct FileSignature: Equatable {
        let size: Int
        let modificationDate: Date
    }

    private static func isStableFile(
        at url: URL,
        minimumAge: TimeInterval,
        checkMilliseconds: Int,
        fileManager: FileManager
    ) async -> Bool {
        guard let initialSignature = fileSignature(at: url, fileManager: fileManager),
              Date().timeIntervalSince(initialSignature.modificationDate) >= minimumAge,
              isCompleteImage(at: url) else {
            return false
        }

        if checkMilliseconds > 0 {
            try? await Task.sleep(for: .milliseconds(checkMilliseconds))
            guard !Task.isCancelled else { return false }
        }

        guard let finalSignature = fileSignature(at: url, fileManager: fileManager),
              initialSignature == finalSignature else {
            return false
        }

        return isCompleteImage(at: url)
    }

    private static func fileSignature(at url: URL, fileManager: FileManager) -> FileSignature? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let modificationDate = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }

        return FileSignature(size: fileSize.intValue, modificationDate: modificationDate)
    }

    private static func isCompleteImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetStatus(source) == .statusComplete
    }
}
