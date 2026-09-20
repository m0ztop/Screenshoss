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
    func testTopTriggerIncludesPhysicalScreenEdge() {
        let screen = CGRect(x: 0, y: 0, width: 2_560, height: 1_440)
        let trigger = CGRect(x: 1_200, y: 1_406, width: 160, height: 34)

        for y in [screen.maxY - 1, screen.maxY] {
            let pointer = CGPoint(x: screen.midX, y: y)
            XCTAssertTrue(ShelfScreenGeometry.containsPointer(pointer, in: screen))
            XCTAssertTrue(ShelfScreenGeometry.containsPointer(pointer, in: trigger))
        }
        XCTAssertFalse(ShelfScreenGeometry.containsPointer(
            CGPoint(x: screen.midX, y: screen.maxY + 1), in: screen
        ))
        XCTAssertFalse(ShelfScreenGeometry.containsPointer(
            CGPoint(x: trigger.maxX + 1, y: screen.maxY), in: trigger
        ))
    }

    func testTopEdgeKeepsOpenPanelRetainedAcrossDisplayOrigins() {
        for origin in [CGPoint.zero, CGPoint(x: -2_560, y: 320)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 2_560, height: 1_440))
            let collapsed = CGRect(x: screen.midX - 80, y: screen.maxY - 34, width: 160, height: 34)
            let expanded = CGRect(x: screen.midX - 590, y: screen.maxY - 476, width: 1_180, height: 476)

            // A stationary pointer at the top edge must not cause the close
            // timer to collapse the panel and then trigger another opening.
            XCTAssertTrue(ShelfScreenGeometry.retainsHover(
                at: CGPoint(x: screen.midX, y: screen.maxY),
                collapsedFrame: collapsed,
                expandedFrame: expanded,
                screenFrame: screen,
                visibleFrame: screen,
                includesMenuBar: true
            ))
            XCTAssertFalse(ShelfScreenGeometry.retainsHover(
                at: CGPoint(x: screen.midX, y: screen.maxY + 1),
                collapsedFrame: collapsed,
                expandedFrame: expanded,
                screenFrame: screen,
                visibleFrame: screen,
                includesMenuBar: true
            ))
        }
    }

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

    func testOpenShelfDoesNotRetainHoverOnAnotherDisplay() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let retained = ShelfScreenGeometry.retainsHover(
            at: CGPoint(x: 2_160, y: 750),
            collapsedFrame: CGRect(x: 640, y: 866, width: 160, height: 34),
            expandedFrame: CGRect(x: 130, y: 392, width: 1_180, height: 476),
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 868),
            includesMenuBar: true
        )

        XCTAssertFalse(retained)
    }

    func testSideShelfHoverPaddingDoesNotExtendOntoAnotherDisplay() {
        let retained = ShelfScreenGeometry.retainsHover(
            at: CGPoint(x: 1_450, y: 450),
            collapsedFrame: CGRect(x: 1_406, y: 370, width: 34, height: 160),
            expandedFrame: CGRect(x: 912, y: 54, width: 520, height: 760),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 868),
            includesMenuBar: false
        )

        XCTAssertFalse(retained)
    }

    func testTopShelfRetainsHoverInItsMenuBarAndInsideItsPadding() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1_440, height: 982)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 908)
        for point in [CGPoint(x: 250, y: 954), CGPoint(x: 120, y: 600)] {
            XCTAssertTrue(ShelfScreenGeometry.retainsHover(
                at: point,
                collapsedFrame: CGRect(x: 640, y: 948, width: 160, height: 34),
                expandedFrame: CGRect(x: 130, y: 432, width: 1_180, height: 476),
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                includesMenuBar: true
            ))
        }
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
