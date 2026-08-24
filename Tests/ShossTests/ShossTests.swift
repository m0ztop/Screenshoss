import XCTest
@testable import Shoss

final class LooksLikeMacScreenshotTests: XCTestCase {

    func testAcceptsDefaultScreenshotName() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-06-03 at 21.05.04.png")
        XCTAssertTrue(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testAcceptsScreenShotWithSpace() {
        let url = URL(fileURLWithPath: "/tmp/Screen Shot 2026-06-03 at 21.05.04.png")
        XCTAssertTrue(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testAcceptsScreenshotDashVariant() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot-2026-06-03-at-21.05.04.png")
        XCTAssertTrue(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testAcceptsScreenShotDashVariant() {
        let url = URL(fileURLWithPath: "/tmp/Screen Shot-2026-06-03-at-21.05.04.png")
        XCTAssertTrue(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testRejectsOrdinaryImageName() {
        let url = URL(fileURLWithPath: "/tmp/IMG_1234.png")
        XCTAssertFalse(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testRejectsOrdinaryHeicImageName() {
        let url = URL(fileURLWithPath: "/tmp/IMG_8237.HEIC")
        XCTAssertFalse(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testAcceptsRenamedImageInsideStorage() {
        let url = URL(fileURLWithPath: "/tmp/client-wireframe.png")
        XCTAssertTrue(ScreenshotItem.isSupportedImageFile(url))
        XCTAssertFalse(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testRejectsUnsupportedExtension() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-06-03 at 21.05.04.gif")
        XCTAssertFalse(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testRejectsBmpExtension() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-06-03 at 21.05.04.bmp")
        XCTAssertFalse(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testRejectsNonImageFile() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-06-03 at 21.05.04.txt")
        XCTAssertFalse(ScreenshotItem.looksLikeMacScreenshot(url))
    }

    func testAcceptsSimpleRenameFilename() {
        XCTAssertTrue(ScreenshotLibrary.isSafeScreenshotFilename("Screenshot 2026-06-03 at 21.05.04.png"))
        XCTAssertTrue(ScreenshotLibrary.isSafeScreenshotFilename("client-wireframe.png"))
    }

    func testRejectsRenameUnsupportedExtension() {
        XCTAssertFalse(ScreenshotLibrary.isSafeScreenshotFilename("client-wireframe.pdf"))
    }

    func testRejectsRenamePathTraversal() {
        XCTAssertFalse(ScreenshotLibrary.isSafeScreenshotFilename("../Screenshot.png"))
        XCTAssertFalse(ScreenshotLibrary.isSafeScreenshotFilename("folder/Screenshot.png"))
        XCTAssertFalse(ScreenshotLibrary.isSafeScreenshotFilename("folder:Screenshot.png"))
    }

    func testRejectsRenameDotSegments() {
        XCTAssertFalse(ScreenshotLibrary.isSafeScreenshotFilename("."))
        XCTAssertFalse(ScreenshotLibrary.isSafeScreenshotFilename(".."))
    }

    func testAcceptsSafeFolderNames() {
        XCTAssertTrue(ScreenshotLibrary.isSafeFolderName("Design"))
        XCTAssertTrue(ScreenshotLibrary.isSafeFolderName("Client Work"))
        XCTAssertTrue(ScreenshotLibrary.isSafeFolderName("Text-Notes"))
    }

    func testRejectsUnsafeFolderNames() {
        XCTAssertFalse(ScreenshotLibrary.isSafeFolderName(""))
        XCTAssertFalse(ScreenshotLibrary.isSafeFolderName("."))
        XCTAssertFalse(ScreenshotLibrary.isSafeFolderName(".."))
        XCTAssertFalse(ScreenshotLibrary.isSafeFolderName(".hidden"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFolderName("../Design"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFolderName("Client/Design"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFolderName("Client:Design"))
    }

    func testAcceptsSafeFavoriteRelativePaths() {
        XCTAssertTrue(ScreenshotLibrary.isSafeFavoriteRelativePath("Screenshot 2026-06-04 at 15.12.10.png"))
        XCTAssertTrue(ScreenshotLibrary.isSafeFavoriteRelativePath("Design/client-wireframe.png"))
    }

    func testRejectsUnsafeFavoriteRelativePaths() {
        XCTAssertFalse(ScreenshotLibrary.isSafeFavoriteRelativePath(""))
        XCTAssertFalse(ScreenshotLibrary.isSafeFavoriteRelativePath("/tmp/Screenshot.png"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFavoriteRelativePath("../Screenshot.png"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFavoriteRelativePath("Design/../Screenshot.png"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFavoriteRelativePath("Design/Nested/Screenshot.png"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFavoriteRelativePath("Design/client-wireframe.pdf"))
        XCTAssertFalse(ScreenshotLibrary.isSafeFavoriteRelativePath(".hidden/Screenshot.png"))
    }
}

final class ShelfScreenGeometryTests: XCTestCase {
    func testDetectsNativeCameraHousingFromSafeAndAuxiliaryAreas() {
        XCTAssertTrue(
            ShelfScreenGeometry.hasCameraHousing(
                safeAreaTopInset: 32,
                auxiliaryTopLeftArea: CGRect(x: 0, y: 968, width: 720, height: 32),
                auxiliaryTopRightArea: CGRect(x: 820, y: 968, width: 620, height: 32)
            )
        )
    }

    func testDoesNotTreatAStandardDisplayAsAComputerWithCameraHousing() {
        XCTAssertFalse(
            ShelfScreenGeometry.hasCameraHousing(
                safeAreaTopInset: 0,
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            )
        )
    }

    func testNativeCameraHousingKeepsCollapsedTargetAtScreenTop() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 868)

        XCTAssertEqual(
            ShelfScreenGeometry.topEdgeY(
                isExpanded: false,
                hasCameraHousing: true,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            ),
            screenFrame.maxY
        )
        XCTAssertEqual(
            ShelfScreenGeometry.topEdgeY(
                isExpanded: true,
                hasCameraHousing: true,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            ),
            visibleFrame.maxY
        )
    }

    func testMenuBarRetentionFrameCoversAreaAboveExpandedPanel() {
        let panelFrame = CGRect(x: 130, y: 392, width: 1_180, height: 476)
        let screenFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 868)
        let retentionFrame = ShelfScreenGeometry.topMenuBarRetentionFrame(
            panelFrame: panelFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertTrue(retentionFrame.contains(CGPoint(x: panelFrame.midX, y: 884)))
        XCTAssertFalse(retentionFrame.contains(CGPoint(x: 20, y: 884)))
    }
}

@MainActor
final class FirstLaunchHintControllerTests: XCTestCase {
    func testDifferentAppInstallationsHaveDifferentIdentifiers() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstURL = rootURL.appendingPathComponent("First.app", isDirectory: true)
        let secondURL = rootURL.appendingPathComponent("Second.app", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        XCTAssertNotEqual(
            FirstLaunchHintController.installationIdentifier(for: firstURL),
            FirstLaunchHintController.installationIdentifier(for: secondURL)
        )
    }
}
