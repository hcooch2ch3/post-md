import XCTest
import AppKit
import SwiftUI
@testable import PostMDCore

/// Covers the dispatch path itself, not just the key matcher. Every earlier defect in this logic
/// shipped because only the pure matcher was reachable from tests.
final class EditDispatchTests: XCTestCase {

    private func makePanel(_ content: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                            styleMask: [.nonactivatingPanel, .borderless, .resizable],
                            backing: .buffered, defer: false)
        panel.contentView = content
        panel.orderFrontRegardless()
        return panel
    }

    private func makeTextView(allowsUndo: Bool = true) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        tv.isEditable = true
        tv.allowsUndo = allowsUndo
        return tv
    }

    private func event(_ key: String, _ code: UInt16, _ window: NSWindow,
                       flags: NSEvent.ModifierFlags = .command) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: key, charactersIgnoringModifiers: key,
                         isARepeat: false, keyCode: code)!
    }

    private func pump(_ seconds: TimeInterval = 0.25) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: Clipboard

    func testClipboardCommandsActOnTheFocusedTextView() {
        let tv = makeTextView()
        let panel = makePanel(tv)
        panel.makeFirstResponder(tv)
        tv.string = "HELLO"
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("SEED", forType: .string)

        XCTAssertTrue(EditDispatch.perform(event("a", 0, panel), in: panel))
        XCTAssertEqual(tv.selectedRange().length, 5)

        XCTAssertTrue(EditDispatch.perform(event("c", 8, panel), in: panel))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "HELLO")

        XCTAssertTrue(EditDispatch.perform(event("x", 7, panel), in: panel))
        XCTAssertEqual(tv.string, "")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("SEED", forType: .string)
        XCTAssertTrue(EditDispatch.perform(event("v", 9, panel), in: panel))
        XCTAssertEqual(tv.string, "SEED", "paste must produce the pasteboard's content, not the old buffer")
    }

    func testUnrelatedShortcutFallsThrough() {
        let tv = makeTextView()
        let panel = makePanel(tv)
        panel.makeFirstResponder(tv)
        XCTAssertFalse(EditDispatch.perform(event("q", 12, panel), in: panel))
        XCTAssertFalse(EditDispatch.perform(event("\r", 36, panel), in: panel), "⌘Return stays the save shortcut")
    }

    /// The regression that started this: a window responds to undo:, so a chain walk claimed ⌘Z
    /// unconditionally — in read mode and with nothing to undo.
    func testUndoIsNotClaimedWhenNothingCanAct() {
        let tv = makeTextView()
        let panel = makePanel(tv)
        panel.makeFirstResponder(tv)
        tv.undoManager?.removeAllActions()
        XCTAssertFalse(EditDispatch.perform(event("z", 6, panel), in: panel), "empty undo stack")

        panel.makeFirstResponder(nil)
        XCTAssertFalse(EditDispatch.perform(event("z", 6, panel), in: panel), "read mode, no text view")
    }

    func testUndoIsNotClaimedWhenUndoIsDisallowed() {
        let tv = makeTextView(allowsUndo: false)
        let panel = makePanel(tv)
        panel.makeFirstResponder(tv)
        XCTAssertFalse(EditDispatch.perform(event("z", 6, panel), in: panel))
    }

    func testUndoAndRedoMoveTheText() {
        let tv = makeTextView()
        let panel = makePanel(tv)
        panel.makeFirstResponder(tv)
        tv.string = ""
        tv.undoManager?.removeAllActions()
        tv.insertText("first", replacementRange: NSRange(location: 0, length: 0))
        tv.breakUndoCoalescing()
        let typed = tv.string

        XCTAssertTrue(EditDispatch.perform(event("z", 6, panel), in: panel))
        XCTAssertNotEqual(tv.string, typed, "⌘Z must actually change the text, not just claim the event")

        XCTAssertTrue(EditDispatch.perform(event("z", 6, panel, flags: [.command, .shift]), in: panel))
        XCTAssertEqual(tv.string, typed)
    }

    // MARK: The SwiftUI binding

    /// The one that matters: the undo manager rewrites the text storage and posts nothing, so the
    /// TextEditor binding kept the PRE-undo string. The sticker showed the undone text while the
    /// draft ⌘Return commits — and auto-writes to the linked file — still held what was undone.
    func testUndoKeepsTheSwiftUIBindingInSync() throws {
        final class Model: ObservableObject { @Published var text = "" }
        struct Editor: View {
            @ObservedObject var m: Model
            var body: some View { TextEditor(text: $m.text) }
        }

        let model = Model()
        let panel = makePanel(NSHostingView(rootView: Editor(m: model)))
        pump(1.0)

        func findTextView(_ v: NSView) -> NSTextView? {
            if let tv = v as? NSTextView { return tv }
            for sub in v.subviews { if let f = findTextView(sub) { return f } }
            return nil
        }
        let tv = try XCTUnwrap(findTextView(panel.contentView!), "SwiftUI TextEditor has no NSTextView")
        panel.makeFirstResponder(tv)

        tv.insertText("abc", replacementRange: NSRange(location: 0, length: 0))
        pump()
        tv.breakUndoCoalescing()
        tv.insertText("d", replacementRange: NSRange(location: tv.string.count, length: 0))
        pump()
        XCTAssertEqual(model.text, tv.string, "precondition: typing keeps the binding in sync")

        XCTAssertTrue(EditDispatch.perform(event("z", 6, panel), in: panel))
        pump()
        XCTAssertEqual(model.text, tv.string,
                       "after ⌘Z the binding must match the visible text — otherwise ⌘Return saves the un-undone draft")
    }
}
