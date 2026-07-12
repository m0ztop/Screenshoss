import CoreGraphics
import Foundation
import ImageIO

struct ScreenshotItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let createdAt: Date
    let fileSize: Int64
    let dimensions: CGSize?
    let folderName: String?
    let isFavorite: Bool

    var relativeCreatedAt: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var dimensionsText: String {
        guard let dimensions else { return "Unknown size" }
        return "\(Int(dimensions.width)) x \(Int(dimensions.height)) px"
    }

    static func make(
        url: URL,
        storageRootURL: URL? = nil,
        favoriteRelativePaths: Set<String> = []
    ) -> ScreenshotItem? {
        let resourceKeys: Set<URLResourceKey> = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let values = try? url.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return nil
        }

        let relativePath = storageRootURL.flatMap { Self.relativePath(for: url, storageRootURL: $0) }
        return ScreenshotItem(
            id: url,
            url: url,
            name: url.lastPathComponent,
            createdAt: values.creationDate ?? values.contentModificationDate ?? Date.distantPast,
            fileSize: Int64(values.fileSize ?? 0),
            dimensions: imageDimensions(at: url),
            folderName: relativePath.flatMap(folderName(forRelativePath:)),
            isFavorite: relativePath.map { favoriteRelativePaths.contains($0) } ?? false
        )
    }

    static func relativePath(for url: URL, storageRootURL: URL) -> String? {
        let rootPath = storageRootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func folderName(forRelativePath relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/")
        guard parts.count > 1 else { return nil }
        return String(parts[0])
    }

    private static func imageDimensions(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
}

struct ScreenshotFolder: Identifiable, Hashable, Sendable {
    let name: String
    let url: URL
    let count: Int

    var id: String { name }
}

extension ScreenshotItem {
    static func isSupportedImageFile(_ url: URL) -> Bool {
        supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    static func looksLikeMacScreenshot(_ url: URL) -> Bool {
        guard isSupportedImageFile(url) else {
            return false
        }

        let lowercasedName = url.deletingPathExtension().lastPathComponent.lowercased()
        return lowercasedName.hasPrefix("screenshot ")
            || lowercasedName.hasPrefix("screen shot ")
            || lowercasedName.hasPrefix("screenshot-")
            || lowercasedName.hasPrefix("screen shot-")
    }

    private static let supportedImageExtensions = ["png", "jpg", "jpeg", "heic", "tiff"]
}
