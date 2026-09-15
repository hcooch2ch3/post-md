import Foundation

/// Per-note monotonic generation counter. Discards out-of-order completions of async file reads via latest-wins.
///
/// `.write`/`.extend` fire immediately with no debounce, and `readLinkedFile` dispatches to a global
/// queue with no ordering guarantee, so on rapid back-to-back saves the completions can reach main in
/// reverse order and the sticker gets stuck lagging behind the file.
/// A read issues a token via `begin` at start, and `isCurrent` at completion checks whether it's still the latest generation, dropping it otherwise.
///
/// Thread contract: **main queue only** (handleFileEvent and completion callbacks are all on main). No locks.
public final class ReadGeneration {
    private var current: [UUID: Int] = [:]

    public init() {}

    /// Starts a new read: bumps this note's generation by 1 and returns the token.
    public func begin(_ id: UUID) -> Int {
        let g = (current[id] ?? 0) + 1
        current[id] = g
        return g
    }

    /// Whether the completion result may be applied: true only when the issued token is still the latest generation.
    public func isCurrent(_ id: UUID, _ token: Int) -> Bool {
        current[id] == token
    }
}
