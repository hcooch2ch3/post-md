import XCTest
@testable import PostMDCore

final class EditShortcutTests: XCTestCase {
    func testClipboardShortcuts() {
        XCTAssertEqual(EditShortcut.command(key: "x", keyCode: 7, command: true), .cut)
        XCTAssertEqual(EditShortcut.command(key: "c", keyCode: 8, command: true), .copy)
        XCTAssertEqual(EditShortcut.command(key: "v", keyCode: 9, command: true), .paste)
        XCTAssertEqual(EditShortcut.command(key: "a", keyCode: 0, command: true), .selectAll)
    }

    func testUndoAndRedoDifferOnlyByShift() {
        XCTAssertEqual(EditShortcut.command(key: "z", keyCode: 6, command: true), .undo)
        XCTAssertEqual(EditShortcut.command(key: "z", keyCode: 6, command: true, shift: true), .redo)
    }

    /// charactersIgnoringModifiers reports an uppercase letter when shift is held.
    func testUppercaseKeyMatches() {
        XCTAssertEqual(EditShortcut.command(key: "Z", keyCode: 6, command: true, shift: true), .redo)
        XCTAssertEqual(EditShortcut.command(key: "A", keyCode: 0, command: true), .selectAll)
    }

    func testWithoutCommandNothingMatches() {
        for key in ["x", "c", "v", "a", "z"] {
            XCTAssertNil(EditShortcut.command(key: key, keyCode: 8, command: false), "bare \(key) must not match")
        }
    }

    /// Swallowing ⌥⌘C or ⌃⌘C would silently break whatever else binds them.
    func testExtraModifiersDoNotMatch() {
        XCTAssertNil(EditShortcut.command(key: "c", keyCode: 8, command: true, option: true))
        XCTAssertNil(EditShortcut.command(key: "c", keyCode: 8, command: true, control: true))
        XCTAssertNil(EditShortcut.command(key: "v", keyCode: 9, command: true, shift: true))
        XCTAssertNil(EditShortcut.command(key: "a", keyCode: 0, command: true, shift: true))
        XCTAssertNil(EditShortcut.command(key: "c", keyCode: 8, command: true, shift: true))
        XCTAssertNil(EditShortcut.command(key: "x", keyCode: 7, command: true, shift: true))
        XCTAssertNil(EditShortcut.command(key: "z", keyCode: 6, command: true, shift: true, option: true))
    }

    /// On a Cyrillic or Greek layout ⌘C reports "с", so the letter can't match. The key code is
    /// positional and still identifies the physical key.
    func testNonLatinLayoutFallsBackToKeyCode() {
        XCTAssertEqual(EditShortcut.command(key: "с", keyCode: 8, command: true), .copy)
        XCTAssertEqual(EditShortcut.command(key: "ф", keyCode: 0, command: true), .selectAll)
        XCTAssertEqual(EditShortcut.command(key: "я", keyCode: 6, command: true), .undo)
        XCTAssertEqual(EditShortcut.command(key: "я", keyCode: 6, command: true, shift: true), .redo)
        XCTAssertNil(EditShortcut.command(key: "й", keyCode: 12, command: true))
        XCTAssertNil(EditShortcut.command(key: "с", keyCode: 8, command: true, option: true))
        XCTAssertNil(EditShortcut.command(key: "с", keyCode: 8, command: true, shift: true))
    }

    /// The character wins over the key code, so a layout that swaps two tracked keys sends the
    /// command its label promises. Turkish F is the real instance: it puts "v" at the US-C position
    /// and "c" at the US-V position.
    func testLetterWinsOverKeyCode() {
        XCTAssertEqual(EditShortcut.command(key: "c", keyCode: 9, command: true), .copy)
    }

    /// A Latin letter that maps to no command must NOT fall back to position. On AZERTY the key at
    /// the US-A position reports "q", so a positional fallback would turn ⌘Q into select-all;
    /// QWERTZ ⌘Y would become undo and Dvorak ⌘J would become copy.
    func testRearrangedLatinLayoutsDoNotFallBackToKeyCode() {
        XCTAssertNil(EditShortcut.command(key: "q", keyCode: 0, command: true))   // AZERTY ⌘Q
        XCTAssertNil(EditShortcut.command(key: "y", keyCode: 6, command: true))   // QWERTZ ⌘Y
        XCTAssertNil(EditShortcut.command(key: "j", keyCode: 8, command: true))   // Dvorak ⌘J
        XCTAssertNil(EditShortcut.command(key: "w", keyCode: 6, command: true))   // AZERTY ⌘W
    }

    func testEverySelectorNameIsWellFormed() {
        for command in EditCommand.allCases {
            XCTAssertTrue(command.selectorName.hasSuffix(":"), "\(command) selector needs an argument")
            XCTAssertFalse(command.selectorName.dropLast().isEmpty, "\(command) selector is empty")
        }
        XCTAssertEqual(EditCommand.selectAll.selectorName, "selectAll:")
        XCTAssertEqual(Set(EditCommand.allCases.map(\.selectorName)).count, EditCommand.allCases.count)
    }

    /// A window responds to undo:/redo: (it forwards to its own undo manager), so a panel that
    /// claimed them via tryToPerform would swallow ⌘Z / ⇧⌘Z unconditionally — in read mode, and
    /// with nothing to undo — and block the menu from routing them. It responds to none of the
    /// other four, so those fall through untouched when nothing handles them.
    func testWindowDispatchableExcludesUndoAndRedo() {
        XCTAssertEqual(EditCommand.windowDispatchable, [.cut, .copy, .paste, .selectAll])
        XCTAssertFalse(EditCommand.windowDispatchable.contains(.undo))
        XCTAssertFalse(EditCommand.windowDispatchable.contains(.redo))
        // Fails when a seventh command is added without deciding how it dispatches.
        XCTAssertEqual(Set(EditCommand.windowDispatchable).union([.undo, .redo]),
                       Set(EditCommand.allCases))
    }

    /// An ASCII character that maps to no command must not fall back to position either. Dvorak –
    /// Right-Handed puts "0" at the US-X position, so ⌘0 would have resolved to cut and destroyed
    /// a selection; Dvorak – Left-Handed puts "-" at US-A and "'" at US-Z.
    func testAsciiPunctuationAndDigitsDoNotFallBackToKeyCode() {
        XCTAssertNil(EditShortcut.command(key: "0", keyCode: 7, command: true))   // Dvorak-R ⌘0
        XCTAssertNil(EditShortcut.command(key: "7", keyCode: 0, command: true))   // Dvorak-R ⌘7
        XCTAssertNil(EditShortcut.command(key: "9", keyCode: 6, command: true))   // Dvorak-R ⌘9
        XCTAssertNil(EditShortcut.command(key: "-", keyCode: 0, command: true))   // Dvorak-L ⌘-
        XCTAssertNil(EditShortcut.command(key: ";", keyCode: 6, command: true))   // Dvorak ⌘;
    }

    /// fn is inside deviceIndependentFlagsMask, so it has to disqualify like option and control.
    func testFunctionModifierDoesNotMatch() {
        XCTAssertNil(EditShortcut.command(key: "c", keyCode: 8, command: true, function: true))
    }

    func testUnrelatedKeysDoNotMatch() {
        XCTAssertNil(EditShortcut.command(key: "q", keyCode: 12, command: true))
        XCTAssertNil(EditShortcut.command(key: "", keyCode: 36, command: true))   // ⌘Return: no character, no match
        XCTAssertNil(EditShortcut.command(key: "\r", keyCode: 36, command: true))   // ⌘Return stays the save shortcut
    }
}
