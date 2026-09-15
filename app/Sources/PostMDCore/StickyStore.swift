import Foundation
import CoreGraphics

public enum StickyStoreError: Error, Equatable {
    case capReached          // sticker count (maxStickies) exceeded
    case contentTooLarge     // content bytes (maxContentBytes) exceeded
    case noteNotFound        // updateContent: the edit-target id doesn't exist (no silent failure)
}

/// Summary of a restore() result. Exposes drop counts so the caller (AppDelegate) can tell the user:
/// "no silent failure": if a note is dropped on restore, surface it to the user the way the receive path does.
public struct RestoreOutcome: Equatable {
    public let restored: Int         // notes actually restored
    public let droppedOversize: Int  // dropped for exceeding content bytes
    public let droppedOverCap: Int   // truncated for exceeding maxStickies
    public var hasDrops: Bool { droppedOversize > 0 || droppedOverCap > 0 }
}

public struct StickyNote: Codable, Identifiable, Equatable {
    public let id: UUID
    public var content: String
    public var frame: CGRect
    public var opacity: Double
    public let createdAt: Date
    public var pinned: Bool? = nil   // whether it's always-on-top (.floating). nil = not pinned. Optional, so the synthesized decoder fills a missing key with nil and v1 notes survive.
    // File linking (convenience feature). nil = standalone sticker. Optional, so the synthesized decoder fills a missing key with nil and existing notes survive (stays schemaVersion 1).
    // Phase 1 stores the values only and leaves stickers editable (standalone). Phase 2 promotes these fields for Live Sync and read-only.
    public var sourcePath: String? = nil       // linked file path
    public var sourceBookmark: Data? = nil     // security-scoped bookmark for tracking file moves (Phase 2)
    public var sourceModifiedDate: Date? = nil // snapshot of the source file mtime: write-back conflict-detection baseline (warns on external change)
    public var color: String? = nil            // sticky-note color palette key (nil = default). The key-to-Color mapping is in the app's StickyPalette.
    public var syncedHash: String? = nil       // content SHA-256 hex at the last sync (nil = unlinked/unseeded). The Live Sync baseline.
}

/// Single source of truth for sticker state. Independent of AppKit window code, so it's unit tested.
/// Save policy: discrete events (add/remove) save immediately; continuous gestures save only on a commit* call.
///
/// Thread contract: **main thread only**. The only callers are AppKit `application(_:open:)` and UI callbacks,
/// all of which run on the main thread. `notes` isn't synchronized, so off-main access is a data race.
public final class StickyStore {
    private static let schemaVersion = 1
    public static let maxStickies = 30
    // Content byte limit: single source for the same value as MAX_CONTENT_BYTES in the extension's limits.ts (app side).
    // Enforced on both write (add) and read (restore) to keep storage and render cost bounded (re-review: restore-path gap).
    public static let maxContentBytes = 1 * 1024 * 1024
    private static let storageKey = "stickyStore.v1"
    private static let cardSize = CGSize(width: 320, height: 240)
    private static let margin: CGFloat = 16
    private static let cascadeOffset: CGFloat = 24

    private struct Container: Codable {
        var schemaVersion: Int
        var notes: [FailableNote]
    }
    /// Per-item failure isolation: a broken item decodes to nil
    private struct FailableNote: Codable {
        let note: StickyNote?
        init(_ note: StickyNote) { self.note = note }
        init(from decoder: Decoder) throws {
            note = try? StickyNote(from: decoder)
        }
        func encode(to encoder: Encoder) throws {
            try note?.encode(to: encoder)
        }
    }

    private let defaults: UserDefaults
    private let screenFrame: CGRect
    public private(set) var notes: [StickyNote] = []

    public init(defaults: UserDefaults, screenFrame: CGRect) {
        self.defaults = defaults
        self.screenFrame = screenFrame
    }

    public func add(content: String) -> Result<StickyNote, StickyStoreError> {
        add(content: content, sourcePath: nil, sourceBookmark: nil)
    }

    /// Create for file linking: also stores the link metadata (sourcePath/sourceBookmark).
    /// Phase 1 stores the values only and leaves the sticker standalone (editable).
    /// The content byte cap and count cap are enforced the same as the plain add.
    public func add(content: String, sourcePath: String?, sourceBookmark: Data?,
                    sourceModifiedDate: Date? = nil) -> Result<StickyNote, StickyStoreError> {
        guard content.utf8.count <= Self.maxContentBytes else { return .failure(.contentTooLarge) }
        guard notes.count < Self.maxStickies else { return .failure(.capReached) }
        let note = StickyNote(
            id: UUID(), content: content,
            frame: nextFrame(index: notes.count),
            opacity: 1.0, createdAt: Date(),
            sourcePath: sourcePath, sourceBookmark: sourceBookmark,
            sourceModifiedDate: sourceModifiedDate,
            // Seed the Live Sync baseline for a linked note at creation, so the returned value type
            // carries it: openFile hands this returned note straight to the VM (StickyNote is a struct,
            // so a later store-side setSyncedHash would NOT reach that already-captured copy). Unlinked → nil.
            syncedHash: sourcePath != nil ? ContentHash.sha256Hex(content) : nil
        )
        notes.append(note)
        save()
        return .success(note)
    }

    /// After a successful write-back, refresh the source mtime so the next save's conflict-detection baseline is current. No-op if the id doesn't exist.
    public func setSourceModifiedDate(id: UUID, date: Date?) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].sourceModifiedDate = date
        save()
    }

    /// Inline edit of standalone sticker content.
    /// - Validation: `.contentTooLarge` when it exceeds `maxContentBytes`
    /// - id missing: `.noteNotFound` (unlike the no-op of the existing commit* family, this reports the save failure)
    /// - Thread: main thread only (store contract)
    /// Phase 1 allows editing regardless of sourcePath. Read-only and unlink transitions are Phase 2.
    @discardableResult
    public func updateContent(id: UUID, content: String) -> Result<Void, StickyStoreError> {
        guard content.utf8.count <= Self.maxContentBytes else { return .failure(.contentTooLarge) }
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return .failure(.noteNotFound) }
        notes[i].content = content
        save()
        return .success(())
    }

    public func remove(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    public func commitFrame(id: UUID, frame: CGRect) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].frame = frame
        save()
    }

    public func commitOpacity(id: UUID, opacity: Double) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].opacity = opacity
        save()
    }

    /// Link a standalone sticker to a file (the inverse of detachFromFile). Sets link metadata and the sync baseline.
    /// Seed `syncedHash` with the just-written content's hash so any initial file-watch event is ignored (self-write ==
    /// baseline → decideSyncAction's !fileChanged guard returns .ignore), not a spurious conflict banner. Content is
    /// unchanged. No-op if the id doesn't exist.
    public func linkToFile(id: UUID, sourcePath: String, sourceBookmark: Data?, syncedHash: String?) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].sourcePath = sourcePath
        notes[i].sourceBookmark = sourceBookmark
        notes[i].syncedHash = syncedHash
        save()
    }

    /// Remove all link metadata, turning it into a standalone sticker. Content is preserved. (unlink)
    public func detachFromFile(id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].sourcePath = nil
        notes[i].sourceBookmark = nil
        notes[i].sourceModifiedDate = nil
        notes[i].syncedHash = nil
        save()
    }

    /// Update the sync baseline (after ⬆️ save/converge/seed). No-op if the id doesn't exist.
    public func setSyncedHash(id: UUID, hash: String?) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].syncedHash = hash
        save()
    }

    /// On move tracking, update the path and refresh the bookmark. No-op if the id doesn't exist.
    public func setSourcePath(id: UUID, path: String, bookmark: Data?) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].sourcePath = path
        notes[i].sourceBookmark = bookmark
        save()
    }

    /// Apply Live Sync (content and hash atomically). On exceeding maxContentBytes: .contentTooLarge, not applied (hash unchanged).
    @discardableResult
    public func applyFileSync(id: UUID, content: String, hash: String) -> Result<Void, StickyStoreError> {
        guard content.utf8.count <= Self.maxContentBytes else { return .failure(.contentTooLarge) }
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return .failure(.noteNotFound) }
        notes[i].content = content
        notes[i].syncedHash = hash
        save()
        return .success(())
    }

    /// Store the sticky-note color palette key (nil = default). No-op if the id doesn't exist (existing setter convention).
    public func setColor(id: UUID, color: String?) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].color = color
        save()
    }

    public func setPinned(id: UUID, pinned: Bool) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].pinned = pinned
        save()
    }

    @discardableResult
    public func restore() -> RestoreOutcome {
        let none = RestoreOutcome(restored: 0, droppedOversize: 0, droppedOverCap: 0)
        guard let data = defaults.data(forKey: Self.storageKey) else { return none }
        let container: Container
        do {
            container = try JSONDecoder().decode(Container.self, from: data)
        } catch {
            NSLog("StickyStore: restore failed (container decode) — %@", "\(error)")  // no silent failure
            return none
        }
        // Migration boundary: don't load an unsupported version (overwriting with v1 would downgrade and lose data).
        guard container.schemaVersion == Self.schemaVersion else {
            NSLog("StickyStore: unsupported schemaVersion %d (supported %d) — skipping restore", container.schemaVersion, Self.schemaVersion)
            return none
        }
        // Restore normalization: so an over-cap store (corruption, downgrade, leftover big notes from an old version)
        // can't cause a flood or render freeze, drop notes over the content byte limit and clamp the count to maxStickies.
        // (re-review MAJOR: closes the gap where restore rendered >1MB notes unguarded, from the old 24MB cap era.)
        // Corrupt items (compactMap nil) are already silently removed by FailableNote isolation. The drop tally here
        // counts only size/count overflow (what the user should be told). The caller uses the tally for the notice.
        let decoded = container.notes.compactMap(\.note)
        let withinSize = decoded.filter { $0.content.utf8.count <= Self.maxContentBytes }
        let clamped = Array(withinSize.prefix(Self.maxStickies))
        notes = clamped
        // syncedHash seeding: for a linked note with no baseline (a Phase 1 save), adopt the sticker
        // content as the baseline. Without it, the first external change gives a spurious banner and ⬆️ detection is undefined (regression).
        var seeded = false
        for i in notes.indices where notes[i].sourcePath != nil && notes[i].syncedHash == nil {
            notes[i].syncedHash = ContentHash.sha256Hex(notes[i].content)
            seeded = true
        }
        let outcome = RestoreOutcome(
            restored: clamped.count,
            droppedOversize: decoded.count - withinSize.count,
            droppedOverCap: withinSize.count - clamped.count
        )
        // If anything was dropped, persist the normalized result right away: compact so a stale over-cap blob
        // doesn't linger until the next mutation (repeating the drop every run, bloating storage) (A-Minor: unsaved gap after restore).
        // If anything was seeded, persist that too (avoids repeated re-seeding on the next run).
        if outcome.hasDrops || seeded { save() }
        return outcome
    }

    private func save() {
        let container = Container(schemaVersion: Self.schemaVersion, notes: notes.map(FailableNote.init))
        do {
            let data = try JSONEncoder().encode(container)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            NSLog("StickyStore: save failed (encode) — %@", "\(error)")  // no silent failure
        }
    }

    /// Cascade anchored at the top-right. Wraps back to the start position when it runs off screen.
    private func nextFrame(index: Int) -> CGRect {
        let startX = screenFrame.maxX - Self.cardSize.width - Self.margin
        let startY = screenFrame.maxY - Self.cardSize.height - Self.margin
        let maxSteps = max(1, Int(min(
            (startX - screenFrame.minX) / Self.cascadeOffset,
            (startY - screenFrame.minY) / Self.cascadeOffset
        )))
        let step = CGFloat(index % maxSteps)
        return CGRect(
            x: startX - step * Self.cascadeOffset,
            y: startY - step * Self.cascadeOffset,
            width: Self.cardSize.width, height: Self.cardSize.height
        )
    }
}
