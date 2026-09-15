import AppKit

/// Runs a standard editing command against a window's own responder chain.
///
/// Lives in Core rather than beside the menu so `swift test` can reach it: the app target is an
/// executable and its top-level code breaks `swift test`, which is how three separate defects in
/// this logic shipped with only the pure key matcher under test.
public enum EditDispatch {
    /// Resolve a key event to an edit command and perform it. Returns false for anything
    /// unrecognized, and for anything nothing can act on, so the event falls through untouched.
    public static func perform(_ event: NSEvent, in window: NSWindow) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let command = EditShortcut.command(key: event.charactersIgnoringModifiers ?? "",
                                                 keyCode: event.keyCode,
                                                 command: flags.contains(.command),
                                                 shift: flags.contains(.shift),
                                                 option: flags.contains(.option),
                                                 control: flags.contains(.control),
                                                 function: flags.contains(.function))
        else { return false }
        return perform(command, in: window)
    }

    /// Split out so tests can drive a command directly, without synthesizing an NSEvent.
    /// The switch is exhaustive on purpose: a seventh command becomes a build error here rather
    /// than silently falling into the undo branch and doing nothing.
    public static func perform(_ command: EditCommand, in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        switch command {
        case .cut, .copy, .paste, .selectAll:
            // tryToPerform walks the chain from this window's own first responder — unlike
            // sendAction(to: nil), which starts at the KEY window and would find nothing while
            // another app holds focus.
            return responder.tryToPerform(Selector(command.selectorName), with: nil)
        case .undo, .redo:
            return performUndoOrRedo(command, on: responder)
        }
    }

    /// Undo and redo can't go through `tryToPerform`: the chain ends at the window, which responds
    /// to `undo:`/`redo:`, so every ⌘Z would be claimed no matter what had focus.
    ///
    /// Note what this is NOT doing. A text view's `undoManager` *is* the window's — same object
    /// (measured). `allowsUndo` is only a proxy for "an editable text view has focus". The whole
    /// behavioral difference is the `canUndo`/`canRedo` gate: claim the event only when there is
    /// something to do, instead of claiming it unconditionally the way the responder chain does.
    ///
    /// `didChangeText()` is load-bearing, not tidiness. The undo manager rewrites the text storage
    /// and posts nothing, so SwiftUI's `TextEditor` binding keeps the PRE-undo string — the sticker
    /// shows the undone text while the draft that ⌘Return commits, and auto-writes to the linked
    /// file, still holds what the user just undid. Verified both the divergence and this fix.
    private static func performUndoOrRedo(_ command: EditCommand, on responder: NSResponder) -> Bool {
        guard let textView = responder as? NSTextView, textView.allowsUndo,
              let manager = textView.undoManager
        else { return false }
        if command == .undo {
            guard manager.canUndo else { return false }
            manager.undo()
        } else {
            guard manager.canRedo else { return false }
            manager.redo()
        }
        textView.didChangeText()
        return true
    }
}
