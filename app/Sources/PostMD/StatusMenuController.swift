import AppKit
import PostMDCore

/// menu-bar icon: the only always-on entry point for an LSUIElement app
final class StatusMenuController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private unowned let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(error: false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        installFileDrop()
    }

    /// drop a .md onto the menu-bar icon → open it as a sticker. Attaches a drop-target view filling the button.
    private func installFileDrop() {
        guard let button = statusItem.button else { return }
        let drop = FileDropView { [weak self] urls in self?.appDelegate.openDroppedFiles(urls) }
        drop.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(drop)
        NSLayoutConstraint.activate([
            drop.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            drop.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            drop.topAnchor.constraint(equalTo: button.topAnchor),
            drop.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    private func setIcon(error: Bool) {
        let symbol = error ? "exclamationmark.triangle.fill" : "note.text"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "post-md")
    }

    /// fallback: notifications may not show (permission denied, etc.), so on error swap the icon to a badge
    /// so the user sees something went wrong without opening the menu. Cleared when the menu opens (= the error is visible at top).
    func indicateError() {
        setIcon(error: true)
    }

    // rebuild from current state each time it opens
    func menuNeedsUpdate(_ menu: NSMenu) {
        setIcon(error: false)
        menu.removeAllItems()

        // recent errors go at the very top so the user sees them before anything else
        if !appDelegate.recentErrors.isEmpty {
            menu.addItem(withTitle: L10n.recentErrorsHeader(), action: nil, keyEquivalent: "")
            for err in appDelegate.recentErrors {
                menu.addItem(withTitle: "  \(String(err.prefix(50)))", action: nil, keyEquivalent: "")
            }
            menu.addItem(.separator())
        }

        // create entry points (convenience features, Phase 1): above the list so the main actions come first.
        menu.addItem(makeItem(L10n.newBlankSticky(), #selector(newBlankSticky)))
        menu.addItem(makeItem(L10n.newFromClipboard(), #selector(newFromClipboard)))
        menu.addItem(makeItem(L10n.openMarkdownFile(), #selector(openFile)))
        menu.addItem(.separator())

        // list only notes that have a live controller: even if store and controllers drift,
        // don't create an item whose click is silently ignored.
        let liveNotes = appDelegate.store.notes.filter { appDelegate.controllers[$0.id] != nil }
        if liveNotes.isEmpty {
            menu.addItem(withTitle: L10n.noStickers(), action: nil, keyEquivalent: "")
        } else {
            for note in liveNotes {
                let preview = note.content
                    .split(separator: "\n").first.map(String.init) ?? L10n.emptyPreview()
                let item = NSMenuItem(
                    title: String(preview.prefix(40)),
                    action: #selector(bringNoteToFront(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = note.id
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        // show the toggle only when stickers exist. Label derives from actual visibility (any visible → "hide", all hidden → "show").
        if !liveNotes.isEmpty {
            if appDelegate.anyStickerVisible {
                menu.addItem(makeItem(L10n.hideAll(), #selector(hideAllStickers)))
            } else {
                menu.addItem(makeItem(L10n.showAll(), #selector(showAllStickers)))
            }
        }
        menu.addItem(makeItem(L10n.bringAllToFront(), #selector(bringAllToFront)))
        // export sticker: list notes in a submenu (keeps the one-click-on-title = bring-forward behavior)
        if !liveNotes.isEmpty {
            let exportItem = NSMenuItem(title: L10n.exportSticker(), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for note in liveNotes {
                let preview = note.content
                    .split(separator: "\n").first.map(String.init) ?? L10n.emptyPreview()
                let sub = NSMenuItem(title: String(preview.prefix(40)),
                                     action: #selector(exportNote(_:)), keyEquivalent: "")
                sub.target = self
                sub.representedObject = note.id
                submenu.addItem(sub)
            }
            exportItem.submenu = submenu
            menu.addItem(exportItem)
        }
        menu.addItem(makeItem(L10n.closeAll(), #selector(closeAll)))
        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.aboutPostMD(), #selector(showAbout)))
        // Language override submenu (System / English / Korean). Checkmark on the active choice.
        let langItem = NSMenuItem(title: L10n.languageMenu(), action: nil, keyEquivalent: "")
        let langSub = NSMenu()
        let options: [(String, LanguageOverride)] = [
            (L10n.languageSystem(), .system),
            (L10n.languageEnglish(), .en),
            (L10n.languageKorean(), .ko),
        ]
        for (title, value) in options {
            let item = NSMenuItem(title: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = (L10n.override == value) ? .on : .off
            langSub.addItem(item)
        }
        langItem.submenu = langSub
        menu.addItem(langItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.quit(), #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func bringNoteToFront(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        appDelegate.controllers[id]?.bringToFrontHighlighted()  // "bring forward + emphasize"
    }
    @objc private func newBlankSticky() { appDelegate.createBlankSticky() }
    @objc private func newFromClipboard() { appDelegate.createStickyFromClipboard() }
    @objc private func openFile() { appDelegate.openMarkdownFile() }
    @objc private func exportNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        appDelegate.exportNote(id: id)
    }
    @objc private func bringAllToFront() {
        appDelegate.controllers.values.forEach { $0.bringToFront() }
    }
    @objc private func hideAllStickers() { appDelegate.hideAllStickers() }
    @objc private func showAllStickers() { appDelegate.showAllStickers() }
    @objc private func closeAll() {
        // close() removes the entry from controllers, so snapshot before iterating (avoid mutation during iteration)
        Array(appDelegate.controllers.values).forEach { $0.close() }
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: L10n.aboutCredits())
        ])
        NSApp.activate()  // activate only for the About panel, as an exception (macOS 14 non-deprecated)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let value = LanguageOverride(rawValue: raw) else { return }
        L10n.override = value
        // The menu rebuilds on next open (menuNeedsUpdate), so labels reflect the new language then.
        // The main menu has no such hook — it is built once — so retitle it by rebuilding here.
        NSApp.mainMenu = EditMenu.makeMainMenu()
    }
}
