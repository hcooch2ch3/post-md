import Foundation

/// One-shot "was this sticker created blank and never filled in?" state, driving the cancel-closes-sticker
/// convenience. Kept as a pure value type so the arm/commit/cancel lifecycle is unit-tested; the SwiftUI view that
/// owns it cannot be instantiated under `swift test`.
///
/// A blank-create sticker opens straight into its first draft. If that first draft is abandoned with nothing typed
/// (whitespace only counts as nothing), the sticker is treated as "never mind" and closed instead of being left empty
/// in read mode. Only the initial blank draft qualifies: once anything has been committed, or the first draft was
/// cancelled, cancel just returns to read mode, so a later "edit, change my mind, Esc" can never remove a sticker.
///
/// Marked (IME-composing) text never reaches the draft string, so an Esc pressed to cancel a composition on the very
/// first draft also closes the sticker; the loss is bounded to that composition, because nothing has ever been
/// committed for such a sticker.
public struct BlankDraftState: Equatable {
    private var armed = false

    public init() {}

    /// Call once, right after the blank-create sticker has actually entered its first edit session.
    /// Arms only when there is no content, so an entrypoint that opens prefilled content in edit mode never arms it.
    public mutating func armForBlankCreate(content: String) {
        armed = content.isEmpty
    }

    /// A successful commit ends the initial draft for good, even if what was committed is empty (an explicit keep).
    public mutating func commit() {
        armed = false
    }

    /// Consumes the one-shot. Returns true when the sticker should close: the initial blank draft was abandoned empty.
    public mutating func cancel(draft: String) -> Bool {
        defer { armed = false }
        return armed && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
