import Foundation

struct ScreenshotImportService: Sendable {
    let desktopURL: URL
    let storageURL: URL
    var stableFileAge: TimeInterval = 2

    func importScreenshots() async -> Bool {
        let desktopURL = desktopURL
        let storageURL = storageURL
        let stableFileAge = stableFileAge

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
                return false
            }

            let screenshots = desktopFiles.filter(ScreenshotItem.looksLikeMacScreenshot)
            var hasPending = false

            for sourceURL in screenshots {
                guard Self.isStableFile(
                    at: sourceURL,
                    minimumAge: stableFileAge,
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
                } catch {
                    hasPending = true
                }
            }

            return hasPending
        }.value
    }

    private static func isStableFile(
        at url: URL,
        minimumAge: TimeInterval,
        fileManager: FileManager
    ) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]),
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let modificationDate = values.contentModificationDate else {
            return false
        }

        return Date().timeIntervalSince(modificationDate) > minimumAge
    }
}
