import XCTest
@testable import PostMDCore

/// Regression: discard out-of-order completions of async file reads with latest-wins,
/// so a sticker cannot get stuck lagging behind the file.
final class ReadGenerationTests: XCTestCase {
    func testStaleGenerationIsDroppedLatestWins() {
        let g = ReadGeneration()
        let id = UUID()
        let t1 = g.begin(id)   // read 1 starts
        let t2 = g.begin(id)   // read 2 starts (newer); assume read 2 completes first
        XCTAssertTrue(g.isCurrent(id, t2), "the latest read-2 completion is applied")
        XCTAssertFalse(g.isCurrent(id, t1), "a late-arriving read-1 completion is discarded (prevents stale stickiness)")
    }

    func testMonotonicAcrossRounds() {
        let g = ReadGeneration()
        let id = UUID()
        _ = g.begin(id)
        let t2 = g.begin(id)
        XCTAssertTrue(g.isCurrent(id, t2))
        let t3 = g.begin(id)          // next round
        XCTAssertFalse(g.isCurrent(id, t2), "the previous generation is invalidated by a new read start")
        XCTAssertTrue(g.isCurrent(id, t3))
    }

    func testPerNoteIndependence() {
        let g = ReadGeneration()
        let a = UUID(); let b = UUID()
        let ta = g.begin(a)
        _ = g.begin(b)                // b's read must not affect a
        XCTAssertTrue(g.isCurrent(a, ta), "another note's read must not touch this note's generation")
    }

    func testUnknownTokenNotCurrent() {
        let g = ReadGeneration()
        XCTAssertFalse(g.isCurrent(UUID(), 1), "a note with no begin has no current token")
    }
}
