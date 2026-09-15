import AppKit
import PostMDCore

final class StickyPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = false   // unpinned by default. applyPinned re-adjusts on pin toggle.
        level = .normal           // default: unpinned (sits under the active app so it doesn't block the screen). On pin, applyPinned sets .floating.
        // keep collectionBehavior (canJoinAllSpaces): Phase 1 keeps following every Space.
        // removing it regresses to off-Space notes being unreachable in a nonactivating app (plan option A). Space scoping is Phase 2 (hub).
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true   // drag the body to move
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // core of a cross-app sticker: it must not hide when another app activates. The NSPanel default
        // varies by config, so pin it explicitly (leaving it unset risks defeating always-visible).
        hidesOnDeactivate = false
        // settled (2026-07-12 GUI check): canBecomeKey=true plus becomesKeyOnlyIfNeeded lets
        // SwiftUI controls (slider/buttons) respond to the mouse. With canBecomeKey=false the controls die and
        // the panel wasn't exposed to the AX tree either (auto-verified). The .nonactivatingPanel styleMask blocks app activation (focus theft),
        // so even when key it keeps the previous app's focus (verified: after a click appActive=false, frontmost unchanged).
        becomesKeyOnlyIfNeeded = true
        minSize = NSSize(width: 180, height: 120)
    }
    override var canBecomeKey: Bool { true }

    /// ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z / ⇧⌘Z inside a sticker.
    ///
    /// This does NOT escape the key-window requirement — AppKit only calls performKeyEquivalent on
    /// the key window, the same precondition a menu key equivalent needs. What it buys is running
    /// FIRST, which is what lets undo repair the SwiftUI binding the menu route silently corrupts
    /// (see EditDispatch.performUndoOrRedo). Whether the menu alone would serve the other four is
    /// still unmeasured; if it would, this override can go.
    ///
    /// super runs first so any view-level shortcut keeps priority over this interceptor. Nothing
    /// collides today — ⌘Return (save) and Esc (cancel) never match — but the order is the invariant.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return EditDispatch.perform(event, in: self)
    }

    /// The level this panel belongs at, pin state and nothing else. MissionControlRaiseKeeper lifts a
    /// panel above its own level for a moment and needs somewhere truthful to drop it back to: reading
    /// `level` at lift time would freeze whatever the pin state happened to be then, and a toggle during
    /// the lift would leave the two disagreeing.
    private(set) var restingLevel: NSWindow.Level = .normal

    /// pin toggle: always-on-top (.floating) ↔ normal (.normal). isFloatingPanel is matched to the level too.
    /// re-assert hidesOnDeactivate=false on every toggle: insurance so the cross-app always-visible invariant (set in init)
    /// isn't shaken by any AppKit flag interaction.
    func applyPinned(_ pinned: Bool) {
        hidesOnDeactivate = false
        restingLevel = pinned ? .floating : .normal
        level = restingLevel
        isFloatingPanel = pinned
    }
}
