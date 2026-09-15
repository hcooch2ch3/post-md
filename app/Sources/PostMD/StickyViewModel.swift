import SwiftUI
import PostMDCore

/// conflict banner state. (Live Sync)
enum SyncBanner: Equatable { case conflict }

/// per-note reactive state: the path that lets Live Sync reach a live sticker view.
/// the old init-seed @State can't push file changes in and goes stale, so the controller updates this vm.
/// threading contract: **main-thread only** (same as StickyStore). AppKit/SwiftUI callbacks all run on main.
/// no @MainActor because it has to be created in the nonisolated StickyPanelController.init, and
/// the codebase enforces main-thread by documented contract rather than an actor.
final class StickyViewModel: ObservableObject {
    @Published var content: String
    @Published var isLinked: Bool                  // whether a file is linked: false on detach → reactively hides 🔗/⬆️
    @Published var syncedHash: String?             // file baseline hash; nil = unlinked / not yet seeded
    @Published var syncBanner: SyncBanner? = nil   // banner on conflict
    @Published var autoSyncPulse: Bool = false     // trigger for the clean auto-sync indicator
    @Published var oversize: Bool = false          // linked file exceeds maxContentBytes
    /// whether an inline edit is in progress: Live Sync reads this as dirty input. Prevents clobbering uncommitted edits.
    private(set) var isEditing: Bool = false

    /// The sticker content differs from the file baseline → there is something to push. Computed from the two
    /// @Published inputs so SwiftUI re-evaluates the ⬆️ enablement reactively; false when unlinked / unseeded.
    var diverged: Bool { SyncDivergence.diverged(contentHash: ContentHash.sha256Hex(content), syncedHash: syncedHash) }

    init(content: String, isLinked: Bool = false, syncedHash: String? = nil) {
        self.content = content
        self.isLinked = isLinked
        self.syncedHash = syncedHash
    }

    func setEditing(_ v: Bool) { isEditing = v }
}
