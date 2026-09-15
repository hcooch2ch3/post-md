import Foundation

/// Whether a linked sticker's content differs from the file baseline (`syncedHash`) — i.e. there is
/// something to push back to the file. A nil baseline (unlinked or not yet seeded) means nothing to push.
public enum SyncDivergence {
    public static func diverged(contentHash: String, syncedHash: String?) -> Bool {
        guard let syncedHash else { return false }
        return contentHash != syncedHash
    }
}
