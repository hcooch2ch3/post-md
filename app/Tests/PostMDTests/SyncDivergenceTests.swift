import XCTest
@testable import PostMDCore

final class SyncDivergenceTests: XCTestCase {
    func testNilBaselineIsNotDiverged() {
        // unlinked / not-yet-seeded → nothing to push
        XCTAssertFalse(SyncDivergence.diverged(contentHash: "abc", syncedHash: nil))
    }
    func testEqualHashIsNotDiverged() {
        XCTAssertFalse(SyncDivergence.diverged(contentHash: "abc", syncedHash: "abc"))
    }
    func testDifferentHashIsDiverged() {
        XCTAssertTrue(SyncDivergence.diverged(contentHash: "abc", syncedHash: "def"))
    }
}
