import XCTest
@testable import PostMDCore

final class SyncDecisionTests: XCTestCase {
    func testNilSyncedHashIgnores() {
        // unseeded → cannot detect external changes, safely ignore
        XCTAssertEqual(decideSyncAction(stickerHash: "s", fileHash: "f", syncedHash: nil, isEditing: false), .ignore)
        XCTAssertEqual(decideSyncAction(stickerHash: "s", fileHash: "f", syncedHash: nil, isEditing: true), .ignore)
    }
    func testFileUnchangedIgnores() {
        // file hash == syncedHash → no real change (touch-only) → ignore (even when dirty)
        XCTAssertEqual(decideSyncAction(stickerHash: "x", fileHash: "base", syncedHash: "base", isEditing: false), .ignore)
        XCTAssertEqual(decideSyncAction(stickerHash: "edited", fileHash: "base", syncedHash: "base", isEditing: true), .ignore)
    }
    func testSeededSelfWriteIgnored() {
        // "Save to file…" seeds syncedHash to the just-written content, then arms the watch. The write's own
        // watcher event has fileHash == syncedHash == stickerHash → ignored (not converged), regardless of edit state.
        // Guards the invariant the link path relies on: seeding must keep the initial self-write from raising a banner.
        XCTAssertEqual(decideSyncAction(stickerHash: "seed", fileHash: "seed", syncedHash: "seed", isEditing: false), .ignore)
        XCTAssertEqual(decideSyncAction(stickerHash: "seed", fileHash: "seed", syncedHash: "seed", isEditing: true), .ignore)
    }
    func testCleanFileChangedAutoApplies() {
        // sticker clean (sticker==synced) + file changed → auto-apply
        XCTAssertEqual(decideSyncAction(stickerHash: "base", fileHash: "new", syncedHash: "base", isEditing: false), .autoApply)
    }
    func testConverged() {
        // file == sticker (both same content) but differs from syncedHash → converged
        XCTAssertEqual(decideSyncAction(stickerHash: "same", fileHash: "same", syncedHash: "old", isEditing: false), .converged)
    }
    func testDirtyFileChangedConflicts() {
        // sticker edited (sticker != synced) + file changed, contents differ → conflict
        XCTAssertEqual(decideSyncAction(stickerHash: "mine", fileHash: "theirs", syncedHash: "base", isEditing: false), .conflict)
    }
    func testEditingTreatedAsDirty() {
        // while editing, treat as dirty even if sticker==synced → conflict (prevents clobbering uncommitted edits)
        XCTAssertEqual(decideSyncAction(stickerHash: "base", fileHash: "new", syncedHash: "base", isEditing: true), .conflict)
    }
}
