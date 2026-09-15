import Foundation

/// Live Sync decision result (the (dirty, file-changed) 2×2).
public enum SyncDecision: Equatable {
    case ignore      // file didn't actually change (touch-only) or unseeded → ignore
    case autoApply   // only the file changed, sticker clean → apply automatically
    case converged   // both reached the same content → update syncedHash only
    case conflict    // sticker dirty + file changed, content differs → conflict banner
}

/// On a FileWatcher event, reads the new file content and decides what to do.
/// - Parameters:
///   - stickerHash: hash of the sticker's current content
///   - fileHash: hash of the new file content
///   - syncedHash: last sync baseline (nil = unseeded)
///   - isEditing: whether an inline edit is in progress (uncommitted draft). Treated as dirty (avoid clobbering an active edit).
public func decideSyncAction(stickerHash: String, fileHash: String, syncedHash: String?, isEditing: Bool) -> SyncDecision {
    // Unseeded (before open/restore seeding) means external changes can't be detected → safely ignore.
    guard let syncedHash else { return .ignore }
    let fileChanged = (fileHash != syncedHash)
    if !fileChanged { return .ignore }                 // F=false guard (up front): prevents a spurious banner from touch-only / self-save re-arm
    if fileHash == stickerHash { return .converged }   // converged
    let dirty = isEditing || (stickerHash != syncedHash)
    return dirty ? .conflict : .autoApply
}
