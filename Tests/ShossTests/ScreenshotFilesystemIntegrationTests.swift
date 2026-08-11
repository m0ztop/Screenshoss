import Foundation
import XCTest
@testable import Shoss

final class ScreenshotFilesystemIntegrationTests: XCTestCase {
    private var temporaryURL: URL!
    private var desktopURL: URL!
    private var storageURL: URL!

    override func setUpWithError() throws {
        temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshossTests-\(UUID().uuidString)", isDirectory: true)
        desktopURL = temporaryURL.appendingPathComponent("Desktop", isDirectory: true)
        storageURL = temporaryURL.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: desktopURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    func testImporterMovesOnlyStableScreenshotFiles() async throws {
        let screenshotURL = desktopURL.appendingPathComponent("Screenshot 2026-07-12 at 12.00.00.png")
        let ordinaryImageURL = desktopURL.appendingPathComponent("holiday.png")
        try Self.writeTestPNG(to: screenshotURL)
        try Self.writeTestPNG(to: ordinaryImageURL)

        let service = ScreenshotImportService(
            desktopURL: desktopURL,
            storageURL: storageURL,
            stableFileAge: -1
        )

        let result = await service.importScreenshots()

        XCTAssertFalse(result.hasPendingFiles)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: storageURL.appendingPathComponent(screenshotURL.lastPathComponent).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ordinaryImageURL.path))
    }

    func testImporterKeepsUnstableScreenshotPending() async throws {
        let screenshotURL = desktopURL.appendingPathComponent("Screenshot 2026-07-12 at 12.00.00.png")
        try Self.writeTestPNG(to: screenshotURL)

        let service = ScreenshotImportService(
            desktopURL: desktopURL,
            storageURL: storageURL,
            stableFileAge: 60
        )

        let result = await service.importScreenshots()
        XCTAssertTrue(result.hasPendingFiles)
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))
    }

    func testStorageScanReadsRootAndFolderImagesAndSkipsSymlinkFolders() async throws {
        let rootImageURL = storageURL.appendingPathComponent("root.png")
        let projectURL = storageURL.appendingPathComponent("Project", isDirectory: true)
        let projectImageURL = projectURL.appendingPathComponent("wireframe.png")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try Self.writeTestPNG(to: rootImageURL)
        try Self.writeTestPNG(to: projectImageURL)

        let externalURL = temporaryURL.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)
        try Self.writeTestPNG(to: externalURL.appendingPathComponent("outside.png"))
        try FileManager.default.createSymbolicLink(
            at: storageURL.appendingPathComponent("Linked", isDirectory: true),
            withDestinationURL: externalURL
        )

        let snapshot = await ScreenshotStorageService(storageURL: storageURL).scan(
            favoriteRelativePaths: ["Project/wireframe.png"]
        )

        XCTAssertEqual(Set(snapshot.items.map(\.name)), ["root.png", "wireframe.png"])
        XCTAssertEqual(snapshot.folders.map(\.name), ["Project"])
        XCTAssertEqual(snapshot.folders.first?.count, 1)
        XCTAssertEqual(snapshot.items.first(where: { $0.name == "wireframe.png" })?.folderName, "Project")
        XCTAssertTrue(snapshot.items.first(where: { $0.name == "wireframe.png" })?.isFavorite == true)
        XCTAssertEqual(snapshot.items.first?.dimensions, CGSize(width: 1, height: 1))
    }

    func testUniqueDestinationAddsIncrementingSuffix() throws {
        let service = ScreenshotStorageService(storageURL: storageURL)
        try Self.writeTestPNG(to: storageURL.appendingPathComponent("shot.png"))
        try Self.writeTestPNG(to: storageURL.appendingPathComponent("shot (1).png"))

        XCTAssertEqual(
            service.uniqueDestinationURL(for: "shot.png", in: storageURL).lastPathComponent,
            "shot (2).png"
        )
    }

    func testStorageScanOrdersNewestFoldersFirst() async throws {
        let olderFolderURL = storageURL.appendingPathComponent("Canvas Style", isDirectory: true)
        let newerFolderURL = storageURL.appendingPathComponent("Ticket", isDirectory: true)
        try FileManager.default.createDirectory(at: olderFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newerFolderURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: olderFolderURL.path
        )
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerFolderURL.path
        )

        let snapshot = await ScreenshotStorageService(storageURL: storageURL).scan(
            favoriteRelativePaths: []
        )

        XCTAssertEqual(snapshot.folders.map(\.name), ["Ticket", "Canvas Style"])
    }

    func testFavoritesPersistAndFollowMovesAndFolderRenames() throws {
        let fileURL = temporaryURL.appendingPathComponent("favorites.json")
        let store = ScreenshotFavoritesStore(fileURL: fileURL)

        try store.toggle("Project/shot.png")
        try store.updatePath(from: "Project/shot.png", to: "Project/renamed.png")
        try store.updateFolderPrefix(from: "Project", to: "Archive")

        let reloadedStore = ScreenshotFavoritesStore(fileURL: fileURL)
        XCTAssertEqual(reloadedStore.relativePaths, ["Archive/renamed.png"])

        try reloadedStore.removeFolderPrefix("Archive")
        XCTAssertTrue(ScreenshotFavoritesStore(fileURL: fileURL).relativePaths.isEmpty)
    }

    @MainActor
    func testLibraryRestoresTrashedScreenshotAndFavoriteState() async throws {
        let screenshotURL = storageURL.appendingPathComponent("favorite.png")
        let favoritesURL = temporaryURL.appendingPathComponent("favorites.json")
        let trashURL = temporaryURL.appendingPathComponent("Trash", isDirectory: true)
        try Self.writeTestPNG(to: screenshotURL)
        try JSONEncoder().encode(["favorite.png"]).write(to: favoritesURL, options: [.atomic])

        let library = ScreenshotLibrary(
            desktopURL: desktopURL,
            storageURL: storageURL,
            favoritesURL: favoritesURL,
            trashService: ScreenshotTrashService(trashDirectoryURL: trashURL)
        )
        await library.refreshAndWaitForTesting()
        let item = try XCTUnwrap(library.items.first)

        library.delete(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotURL.path))
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertEqual(library.screenshotDeleteGeneration, 1)
        XCTAssertEqual(library.trashUndoNotice?.itemCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: trashURL.appendingPathComponent("favorite.png").path
        ))

        library.undoLastTrash()
        await library.refreshAndWaitForTesting()

        XCTAssertNil(library.trashUndoNotice)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))
        XCTAssertEqual(
            library.items.first?.url.resolvingSymlinksInPath(),
            screenshotURL.resolvingSymlinksInPath()
        )
        XCTAssertTrue(library.items.first?.isFavorite == true)
    }

    @MainActor
    func testLibraryImportsAndPublishesFilesystemState() async throws {
        let screenshotURL = desktopURL.appendingPathComponent("Screenshot 2026-07-12 at 12.00.00.png")
        try Self.writeTestPNG(to: screenshotURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -10)],
            ofItemAtPath: screenshotURL.path
        )

        let library = ScreenshotLibrary(
            desktopURL: desktopURL,
            storageURL: storageURL,
            favoritesURL: temporaryURL.appendingPathComponent("favorites.json")
        )
        await library.refreshAndWaitForTesting()

        XCTAssertEqual(library.items.map(\.name), [screenshotURL.lastPathComponent])
        XCTAssertEqual(library.selectedItem?.name, screenshotURL.lastPathComponent)
        XCTAssertEqual(library.selectedItemIDs.count, 1)
        XCTAssertEqual(library.screenshotImportGeneration, 1)
    }

    private static func writeTestPNG(to url: URL) throws {
        let data = Data(base64Encoded: Self.onePixelPNG)!
        try data.write(to: url, options: [.atomic])
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}

final class ScreenshotSelectionServiceTests: XCTestCase {
    func testRangeToggleAndReconcileSelection() {
        let items = (0..<4).map(Self.makeItem)
        var service = ScreenshotSelectionService()

        service.setSingle(items[0])
        service.selectRange(through: items[2], in: items)
        XCTAssertEqual(service.selectedIDs, Set(items[0...2].map(\.id)))

        service.toggle(items[1], in: items)
        XCTAssertEqual(service.selectedIDs, [items[0].id, items[2].id])

        service.reconcile(
            previousSelectedURL: items[2].url,
            allItems: items,
            visibleItems: [items[2], items[3]]
        )
        XCTAssertEqual(service.selectedIDs, [items[2].id])
        XCTAssertEqual(service.selectedItem, items[2])
    }

    private static func makeItem(index: Int) -> ScreenshotItem {
        let url = URL(fileURLWithPath: "/tmp/selection-\(index).png")
        return ScreenshotItem(
            id: url,
            url: url,
            name: url.lastPathComponent,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            fileSize: 1,
            dimensions: CGSize(width: 1, height: 1),
            folderName: nil,
            isFavorite: false
        )
    }
}
