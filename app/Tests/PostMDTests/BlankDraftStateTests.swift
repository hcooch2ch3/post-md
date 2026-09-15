import XCTest
@testable import PostMDCore

final class BlankDraftStateTests: XCTestCase {
    // The initial blank draft, abandoned with nothing typed, closes the sticker.
    func testBlankCreateCancelledEmptyCloses() {
        var s = BlankDraftState()
        s.armForBlankCreate(content: "")
        XCTAssertTrue(s.cancel(draft: ""))
    }

    // Whitespace and newlines count as nothing typed.
    func testBlankCreateCancelledWhitespaceCloses() {
        var s = BlankDraftState()
        s.armForBlankCreate(content: "")
        XCTAssertTrue(s.cancel(draft: "  \n\t "))
    }

    // Typing anything on the first draft and then cancelling only reverts; the sticker stays.
    func testBlankCreateCancelledWithTextStays() {
        var s = BlankDraftState()
        s.armForBlankCreate(content: "")
        XCTAssertFalse(s.cancel(draft: " 가 "))
    }

    // Regression: a committed sticker must never be closed by a later cancel, even if its content is empty again.
    // The first version keyed this off a construction-time constant, which stayed armed for the sticker's whole life.
    func testCommitDisarmsForGood() {
        var s = BlankDraftState()
        s.armForBlankCreate(content: "")
        s.commit()                                   // ⌘Return on the first draft (possibly still empty: explicit keep)
        XCTAssertFalse(s.cancel(draft: ""))          // later: edit, change my mind, Esc
        XCTAssertFalse(s.cancel(draft: "   "))
    }

    // Cancel consumes the one-shot: a second cancel in a later session never closes.
    func testCancelConsumesOneShot() {
        var s = BlankDraftState()
        s.armForBlankCreate(content: "")
        XCTAssertFalse(s.cancel(draft: "typed"))     // first draft cancelled with text: stays
        XCTAssertFalse(s.cancel(draft: ""))          // later session, empty draft: still stays
    }

    // Opening prefilled content in edit mode never arms the close, whatever the entrypoint claims.
    func testPrefilledContentNeverArms() {
        var s = BlankDraftState()
        s.armForBlankCreate(content: "existing")
        XCTAssertFalse(s.cancel(draft: ""))
    }

    // Never armed at all (ordinary stickers): cancel is always a plain revert.
    func testUnarmedNeverCloses() {
        var s = BlankDraftState()
        XCTAssertFalse(s.cancel(draft: ""))
    }
}
