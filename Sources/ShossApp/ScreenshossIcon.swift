import AppKit
import SwiftUI

enum ScreenshossIcon {
    static let image: NSImage? = loadTemplateImage()

    private static func loadTemplateImage() -> NSImage? {
        let logicalSize = NSSize(width: 18, height: 18)
        let bundledURLs = [
            Bundle.main.url(forResource: "statusbar", withExtension: "png"),
            Bundle.main.url(forResource: "statusbar@2x", withExtension: "png")
        ].compactMap { $0 }

        if let image = makeTemplateImage(from: bundledURLs, logicalSize: logicalSize) {
            return image
        }

        let assetsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets", isDirectory: true)
        return makeTemplateImage(
            from: [
                assetsURL.appendingPathComponent("statusbar.png"),
                assetsURL.appendingPathComponent("statusbar@2x.png")
            ],
            logicalSize: logicalSize
        )
    }

    private static func makeTemplateImage(from urls: [URL], logicalSize: NSSize) -> NSImage? {
        let image = NSImage(size: logicalSize)

        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            guard let sourceImage = NSImage(contentsOf: url) else { continue }
            for representation in sourceImage.representations {
                representation.size = logicalSize
                image.addRepresentation(representation)
            }
        }

        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = "Screenshoss"
        return image
    }
}

struct ScreenshossIconView: View {
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image = ScreenshossIcon.image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
            } else {
                Image(systemName: "camera.viewfinder")
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .foregroundStyle(.white)
        .accessibilityLabel("Screenshoss")
    }
}
