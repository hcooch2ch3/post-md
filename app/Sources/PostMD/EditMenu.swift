import AppKit
import PostMDCore

/// The standard text-editing commands: the Edit menu that carries them, and the dispatch that
/// actually fires them inside a sticker.
///
/// Why this exists: post-md is an `LSUIElement` agent app whose stickers are nonactivating
/// panels, so it never had a main menu at all — leaving AppKit nowhere to match ⌘X / ⌘C / ⌘V / ⌘A.
/// Typing into a sticker worked; cut, copy, paste and select-all did nothing.
///
/// The menu is justified on its own: it gives the app's other AppKit UI (the filename field in the
/// open/save panels, alerts) the Edit commands it never had.
///
/// Whether the menu ALONE would also fix the stickers is **unresolved**. Menu key equivalents are
/// resolved against the **key window's** responder chain, and a sticker panel is deliberately
/// nonactivating — but `becomesKeyOnlyIfNeeded` is exactly what makes a click into the text view
/// hand the panel key status, so it may well be key at the moment the user types. That state could
/// not be reproduced in-process (an LSUIElement app cannot activate itself, and programmatic
/// `makeKey` is a no-op under `becomesKeyOnlyIfNeeded`), so it was never measured either way;
/// settling it needs one real keypress with a log inside `performKeyEquivalent`.
///
/// So `StickyPanel.performKeyEquivalent` also resolves the shortcut itself and hands it to its own
/// first responder, which works regardless. Dispatch is deliberately limited to the commands a
/// window cannot falsely claim — see `EditCommand.windowDispatchable`.
enum EditMenu {
    /// One row per command — `EditCommand.allCases` order, so a new case that is never given a title
    /// here fails the assertion below rather than silently vanishing from the menu.
    private struct Row {
        let command: EditCommand
        let title: () -> String     // resolved at build time so a language switch retitles the menu
        let key: String
    }

    private static let rows: [Row] = [
        Row(command: .undo, title: { L10n.undo() }, key: "z"),
        Row(command: .redo, title: { L10n.redo() }, key: "z"),
        Row(command: .cut, title: { L10n.cut() }, key: "x"),
        Row(command: .copy, title: { L10n.copy() }, key: "c"),
        Row(command: .paste, title: { L10n.paste() }, key: "v"),
        Row(command: .selectAll, title: { L10n.selectAll() }, key: "a"),
    ]

    /// Selectors come from Core's table, which `swift test` covers for completeness and shape.
    /// `verifySelectorTable` cross-checks the four clipboard entries against compile-checked
    /// `#selector`s, catching a typo like "cutt:" that a string alone would let through. It cannot
    /// cover `undo:`/`redo:` — `#selector` has no expressible form for them — and it is a debug-only
    /// guard (`assert` is stripped under `-O`, and this target is out of reach of `swift test`).
    private static func verifySelectorTable() {
        let compileChecked: [EditCommand: Selector] = [
            .cut: #selector(NSText.cut(_:)), .copy: #selector(NSText.copy(_:)),
            .paste: #selector(NSText.paste(_:)), .selectAll: #selector(NSText.selectAll(_:)),
        ]
        for (command, expected) in compileChecked {
            assert(Selector(command.selectorName) == expected,
                   "EditCommand.\(command).selectorName does not match its #selector")
        }
    }

    // MARK: Menu

    /// Build the main menu. AppKit always treats the first submenu as the application menu, so a
    /// placeholder app item comes first and the Edit menu second.
    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        // The app submenu stays empty: an accessory (LSUIElement) app shows no menu bar even while
        // active, so there is nothing here for a user to see. Key equivalents still match without
        // one. The app's own commands live in the status menu, which is the surface people use.
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "post-md")   // app name, untranslated by convention
        main.addItem(appItem)

        let editItem = NSMenuItem()
        editItem.submenu = makeEditMenu()
        main.addItem(editItem)

        return main
    }

    static func makeEditMenu() -> NSMenu {
        // Coverage, not order — the menu is free to be reordered.
        assert(Set(rows.map(\.command)) == Set(EditCommand.allCases), "every EditCommand needs a menu row")
        verifySelectorTable()
        let menu = NSMenu(title: L10n.edit())
        for row in rows {
            if row.command == .cut { menu.addItem(.separator()) }   // undo/redo above, clipboard below
            let item = menu.addItem(withTitle: row.title(), action: Selector(row.command.selectorName),
                                    keyEquivalent: row.key)
            if row.command == .redo { item.keyEquivalentModifierMask = [.command, .shift] }
        }
        return menu
    }
}
