import XCTest
@testable import PostMDCore

/// The scan decides which stickers get protected while macOS hands the front app back after a
/// Mission Control selection. Over-collecting raises a sticker the user never asked to see;
/// under-collecting loses one they were already looking at.
final class WindowStackScanTests: XCTestCase {
    private let ours: Int32 = 100
    private let other: Int32 = 200
    private let dock: Int32 = 300
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    private func window(_ number: Int, _ pid: Int32, layer: Int = 0, alpha: Double = 1,
                        on frame: CGRect? = nil) -> ScannedWindow {
        ScannedWindow(number: number, pid: pid, layer: layer, alpha: alpha,
                      bounds: (frame ?? screen).insetBy(dx: 10, dy: 10))
    }

    private func scan(_ windows: [ScannedWindow], ignoring: Set<Int32> = [], on frame: CGRect? = nil) -> [Int] {
        WindowStackScan.windowNumbersAboveOtherApps(
            in: windows, ourPID: ours, screen: frame ?? screen, ignoredPIDs: ignoring
        )
    }

    func testStopsAtTheFirstOtherAppWindow() {
        let result = scan([window(1, ours), window(2, ours), window(3, other), window(4, ours)])
        XCTAssertEqual(result, [1, 2], "windows below another app's front window are already covered")
    }

    func testFrontToBackOrderIsPreserved() {
        XCTAssertEqual(scan([window(7, ours), window(3, ours), window(9, other)]), [7, 3])
    }

    func testEmptyWhenAnotherAppIsAlreadyInFront() {
        XCTAssertEqual(scan([window(1, other), window(2, ours)]), [])
    }

    func testSystemUIDoesNotEndTheWalk() {
        // The Dock owns layer-0 windows while Mission Control is up, which is exactly when this runs.
        let result = scan([window(1, dock), window(2, ours), window(3, other)], ignoring: [dock])
        XCTAssertEqual(result, [2], "a Dock window is skipped, not treated as the boundary")
    }

    func testUnignoredSystemUIStillEndsTheWalk() {
        XCTAssertEqual(scan([window(1, dock), window(2, ours)]), [],
                       "without the exemption the same window is an ordinary boundary")
    }

    func testChromeAboveTheCutoffLayerIsIgnored() {
        let result = scan([window(1, other, layer: 25), window(2, ours), window(3, other)])
        XCTAssertEqual(result, [2], "the menu bar and Dock icons sit above every app and are not the boundary")
    }

    func testOurOwnPanelAboveTheCutoffLayerIsNotCollected() {
        XCTAssertEqual(scan([window(1, ours, layer: 25), window(2, ours), window(3, other)]), [2])
    }

    func testInvisibleWindowsAreSkipped() {
        let result = scan([window(1, other, alpha: 0), window(2, ours), window(3, other)])
        XCTAssertEqual(result, [2], "a fully transparent window covers nothing")
    }

    func testTranslucentStickersAreStillCollected() {
        // The opacity slider bottoms out well above the alpha cutoff; a faded sticker still counts.
        XCTAssertEqual(scan([window(1, ours, alpha: 0.3), window(2, other)]), [1])
    }

    func testAnotherDisplayDoesNotEndTheWalk() {
        let result = scan([window(1, other, on: secondScreen), window(2, ours), window(3, other)])
        XCTAssertEqual(result, [2], "stacking on a display we are not raising into is not our business")
    }

    func testStickersOnAnotherDisplayAreNotCollected() {
        let result = scan([window(1, ours, on: secondScreen), window(2, ours), window(3, other)])
        XCTAssertEqual(result, [2], "a sticker on another display has no raise to lose here")
    }

    func testScanningTheSecondDisplayCollectsItsOwnStickers() {
        let windows = [window(1, ours, on: secondScreen), window(2, ours), window(3, other, on: secondScreen)]
        XCTAssertEqual(scan(windows, on: secondScreen), [1])
    }

    func testEmptyInput() {
        XCTAssertEqual(scan([]), [])
    }

    func testAllOursAndNoBoundary() {
        XCTAssertEqual(scan([window(1, ours), window(2, ours)]), [1, 2])
    }
}
