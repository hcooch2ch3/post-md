import AppKit
import SwiftUI
import PostMDCore

/// Lifecycle of one sticky window. Resizes commit in windowDidEndLiveResize; moves commit via a debounce.
/// Threading contract: main-thread only (same as StickyStore: UI callbacks and URL handlers all run on main).
final class StickyPanelController: NSObject, NSWindowDelegate {
    let noteID: UUID
    let vm: StickyViewModel                 // reactive view state, updated by Live Sync
    private let panel: StickyPanel
    private let store: StickyStore
    private let onClosed: (UUID) -> Void
    private var moveDebounce: Timer?
    private var committedOpacity: Double   // baseline for highlight restore (instead of panel.alphaValue's transient value)
    private var isFlashing = false         // re-entrancy guard for the highlight

    init(note: StickyNote, store: StickyStore,
         startEditing: Bool = false,
         onClosed: @escaping (UUID) -> Void,
         onSaveToFile: @escaping (UUID) -> Bool = { _ in false },
         onError: @escaping (String) -> Void = { _ in },
         onTakeFile: @escaping (UUID) -> Void = { _ in },
         onDetach: @escaping (UUID) -> Void = { _ in },
         onReveal: @escaping (UUID) -> Void = { _ in },
         onOpenEditor: @escaping (UUID) -> Void = { _ in },
         onSaveToNewFile: @escaping (UUID) -> Void = { _ in }) {
        self.noteID = note.id
        self.store = store
        self.onClosed = onClosed
        self.committedOpacity = note.opacity
        self.panel = StickyPanel(frame: note.frame)
        let isLinked = note.sourcePath != nil   // file-linked sticker → show 🔗/⬆️
        self.vm = StickyViewModel(content: note.content, isLinked: isLinked, syncedHash: note.syncedHash)
        super.init()

        panel.alphaValue = note.opacity
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: StickyContentView(
            vm: vm,
            initialOpacity: note.opacity,
            initialPinned: note.pinned == true,
            startEditing: startEditing,
            onClose: { [weak self] in self?.close() },
            onTogglePin: { [weak self] pinned in         // genuine pin wiring; initial apply happens at creation
                guard let self else { return }
                self.store.setPinned(id: self.noteID, pinned: pinned)
                self.panel.applyPinned(pinned)
            },
            onOpacityChange: { [weak self] v in self?.panel.alphaValue = v },
            onOpacityCommit: { [weak self] v in
                guard let self else { return }
                self.panel.alphaValue = v
                self.committedOpacity = v
                self.store.commitOpacity(id: self.noteID, opacity: v)
            },
            // inline-edit save (S1). Phase 1 allows editing on every sticker; read-only is Phase 2.
            // returns success: on failure (over 1MB) the view keeps editing and we notify the user here (no silent failures).
            onContentChange: { [weak self] newContent in
                guard let self else { return false }
                switch self.store.updateContent(id: self.noteID, content: newContent) {
                case .success:
                    return true
                case .failure(.contentTooLarge):
                    onError(L10n.contentTooLargeMB())
                    return false
                case .failure:
                    onError(L10n.couldNotSaveEdits())
                    return false
                }
            },
            // File actions are wired unconditionally (not gated on the initial link state): the view renders each
            // one on `vm.isLinked`, which flips live when a standalone sticker is saved+linked via "Save to file…".
            // Each handler no-ops on a still-unlinked sticker (guarding on sourcePath / resolveSourceURL), so the
            // wiring is inert until the note is actually linked.
            onSaveToFile: { [weak self] in
                guard let self else { return false }
                return onSaveToFile(self.noteID)   // push current content back to the source file; returns success for the check/X flash
            },
            initialColor: note.color,
            onColorChange: { [weak self] key in
                guard let self else { return }
                self.store.setColor(id: self.noteID, color: key)
            },
            onTakeFile: { [weak self] in
                guard let self else { return }
                onTakeFile(self.noteID)   // conflict banner "pull file content"
            },
            onDetach: { [weak self] in guard let self else { return }; onDetach(self.noteID) },
            onRevealInFinder: { [weak self] in guard let self else { return }; onReveal(self.noteID) },
            onOpenInEditor: { [weak self] in guard let self else { return }; onOpenEditor(self.noteID) },
            onSaveToNewFile: { [weak self] in guard let self else { return }; onSaveToNewFile(self.noteID) }  // standalone → save to a new file and link
        ))
        // apply the saved pin state to the window level on restore/create (applyPinned is required on restore)
        panel.applyPinned(note.pinned == true)
    }

    deinit { moveDebounce?.invalidate() }

    /// if the move debounce still has a pending commit, commit it now (avoids losing the final position at app quit).
    /// applicationWillTerminate calls this on every controller.
    func flushPendingMove() {
        guard moveDebounce != nil else { return }
        moveDebounce?.invalidate()
        moveDebounce = nil
        store.commitFrame(id: noteID, frame: panel.frame)
    }

    func show() { panel.orderFrontRegardless() }
    /// Blank-create only: make the panel key so the auto-entered TextEditor receives keystrokes.
    /// `.nonactivatingPanel` means keying does not activate the app (the frontmost app keeps focus).
    /// The actual edit-mode entry is driven by the view's `startEditing` in onAppear. Never add NSApp.activate() here.
    func focusForEditing() { panel.makeKeyAndOrderFront(nil) }
    func hide() { panel.orderOut(nil) }   // non-destructive hide: note and controller stay alive (unlike close)
    var isVisible: Bool { panel.isVisible }   // false after orderOut. Lets menu labels derive from actual visibility.
    func bringToFront() { panel.orderFrontRegardless() }

    /// "bring forward + emphasize": a flash that briefly drops alpha then restores it.
    /// the restore baseline is committedOpacity (the committed value), not panel.alphaValue (transient):
    /// this stops a restore to the wrong value during re-entry or slider drags.
    func bringToFrontHighlighted() {
        panel.orderFrontRegardless()
        guard !isFlashing else { return }   // ignore re-entry while one is in flight
        isFlashing = true
        let base = committedOpacity
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = max(0.3, base - 0.5)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.panel.animator().alphaValue = self.committedOpacity   // restore to the latest committed value
            }, completionHandler: { [weak self] in
                self?.isFlashing = false
            })
        })
    }

    func close() {
        moveDebounce?.invalidate()   // clear the pending move commit (no flush needed since we're past remove)
        moveDebounce = nil
        store.remove(id: noteID)
        panel.orderOut(nil)
        onClosed(noteID)
    }

    // MARK: NSWindowDelegate: continuous gestures save only at the end
    // AppKit has no "drag ended" notification, and windowDidMove fires repeatedly during a drag.
    // the Timer runs in .default runloop mode, so it doesn't fire mid-drag (.eventTracking), only after
    // mouseUp = a gesture-end commit. In .common mode it would fire mid-drag and violate the save-at-end rule.
    func windowDidMove(_ notification: Notification) {
        moveDebounce?.invalidate()
        moveDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.store.commitFrame(id: self.noteID, frame: self.panel.frame)
            self.moveDebounce = nil
        }
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        moveDebounce?.invalidate()   // avoid a double commit when a resize also moves the origin
        moveDebounce = nil
        store.commitFrame(id: noteID, frame: panel.frame)
    }
}
