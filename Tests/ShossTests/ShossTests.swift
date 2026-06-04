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
