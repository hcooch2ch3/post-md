import AppKit
import UserNotifications
import UniformTypeIdentifiers
import PostMDCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var store: StickyStore!
    private(set) var controllers: [UUID: StickyPanelController] = [:]  // strong reference; drop it and the panel disappears
    private(set) var recentErrors: [String] = []  // menu bar "Recent errors"
    private var statusMenu: StatusMenuController!
    let fileWatcher = FileWatcher()               // Live Sync: watch linked sticker files
    private var suppressedNotes: Set<UUID> = []   // ⬆️ suppress the self-write right after saving
    private let readGen = ReadGeneration()        // discard out-of-order file-read completions: latest-wins
    private let raiseKeeper = MissionControlRaiseKeeper()   // a Mission Control raise gets undone without this

    // The "hide/show all" toggle label derives from actual window visibility, not a separate state bool
    // (a global bool drifts from per-window state and the label lies).
    var anyStickerVisible: Bool { controllers.values.contains { $0.isVisible } }

    // Cheap URL length cap before parsing (cut abnormally large URLs before decoding). The exact content byte
    // limit is enforced from a single source, StickyStore.maxContentBytes, on both add() and restore() (re-review: unify the constant, close the restore gap).
    private let maxReceivedURLLength = 2 * 1024 * 1024

    // Queue for URLs that arrive before launch finishes (prevents a store-nil crash). Empty on the normal path, but it enforces the ordering invariant.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiseKeeper.start()

        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        store = StickyStore(defaults: .standard, screenFrame: screen)

        // Stand up the menu bar before handling URLs so reportError's badge display is valid afterward
        statusMenu = StatusMenuController(appDelegate: self)

        // Without a main menu there is nothing to match ⌘X/⌘C/⌘V/⌘A against, so the clipboard
        // shortcuts never reach the sticker's text view. See EditMenu.
        NSApp.mainMenu = EditMenu.makeMainMenu()

        // Notification permission: request on first launch (requesting at the first error would swallow that error)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        verifySchemeHandler()

        restoreStickies()

        // Handle URLs queued before launch
        let queued = pendingURLs
        pendingURLs = []
        queued.forEach(handle(url:))
    }

    // On app quit, flush pending move commits to avoid losing the final position if we quit inside the debounce window (300ms)
    func applicationWillTerminate(_ notification: Notification) {
        controllers.values.forEach { $0.flushPendingMove() }
        fileWatcher.unwatchAll()   // clean up Live Sync watches
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // If the store isn't up yet (before launch), queue and handle at launch
        guard store != nil else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        urls.forEach(handle(url:))
    }

    private func handle(url: URL) {
        // Cheap URL length cut before parsing (block huge URLs before decoding, by byte count). The exact content limit is enforced by store.add().
        // Measure bytes with .utf8.count so a rogue URL full of multibyte chars can't dodge the cut by undercounting via grapheme count.
        guard url.absoluteString.utf8.count <= maxReceivedURLLength else {
            reportError(L10n.contentTooLarge())
            return
        }
        switch StickyURLParser.parse(url) {
        case .success(.new(let content)):
            createSticky(content: content)   // the content byte cap is enforced by store.add() (single source)
        case .success(.open(let path)):
            // A URL can come from anywhere: validate the path (existing markdown/text file) before opening it.
            // openFile(at:) then reads it, stores the bookmark, seeds syncedHash, and arms the watcher → born linked.
            guard let fileURL = LinkablePath.validate(path) else {
                reportError(L10n.cannotOpenLinkedFile())
                return
            }
            reportOpenFailure(openFile(at: fileURL), fileURL.lastPathComponent)
        case .failure(let error):
            reportError(errorMessage(for: error))
        }
    }

    private func createSticky(content: String, startEditing: Bool = false) {
        switch store.add(content: content) {
        case .success(let note):
            addController(for: note, startEditing: startEditing)   // a new sticker comes up via show() → anyStickerVisible becomes true automatically
        case .failure(.capReached):
            reportError(L10n.maxStickiesReached(StickyStore.maxStickies))
        case .failure(.contentTooLarge):
            reportError(L10n.contentTooLargeMB())
        case .failure(.noteNotFound):
            break   // add never returns this error (defensive, to make the switch exhaustive)
        }
    }

    private func restoreStickies() {
        let outcome = store.restore()
        for note in store.notes {
            addController(for: note)
        }
        // If restore dropped any notes, tell the user instead of failing silently (consistent with the receive path).
        guard outcome.hasDrops else { return }
        var parts: [String] = []
        if outcome.droppedOversize > 0 { parts.append(L10n.restoreOversize(outcome.droppedOversize)) }
        if outcome.droppedOverCap > 0 { parts.append(L10n.restoreOverCap(outcome.droppedOverCap)) }
        reportError(L10n.restoreFailed(parts.joined(separator: ", ")))
    }

    private func addController(for note: StickyNote, startEditing: Bool = false) {
        let controller = StickyPanelController(
            note: note, store: store, startEditing: startEditing,
            onClosed: { [weak self] id in
                self?.fileWatcher.unwatch(noteID: id)   // clean up the watch on close (leak prevention)
                self?.controllers[id] = nil
            },
            onSaveToFile: { [weak self] id in self?.saveNoteToSourceFile(id: id) ?? false },
            onError: { [weak self] message in self?.reportError(message) },
            onTakeFile: { [weak self] id in self?.takeFileForNote(id: id) },
            onDetach: { [weak self] id in self?.detachNote(id: id) },
            onReveal: { [weak self] id in self?.revealNoteInFinder(id: id) },
            onOpenEditor: { [weak self] id in self?.openNoteInEditor(id: id) },
            onSaveToNewFile: { [weak self] id in self?.saveNoteToNewFile(id: id) }
        )
        controllers[note.id] = controller
        controller.show()
        // Blank-create path: make the panel key so the auto-entered TextEditor receives keystrokes.
        // (.nonactivatingPanel keeps the frontmost app's focus. Never call NSApp.activate() here — it would steal focus.)
        if startEditing { controller.focusForEditing() }
        // If it's a linked sticker, arm the Live Sync watch
        if note.sourcePath != nil, let url = resolveSourceURL(note: note) {
            fileWatcher.watch(noteID: note.id, url: url) { [weak self] in
                self?.handleFileEvent(noteID: note.id)
            }
        }
    }

    /// FileWatcher event → off-main read → decide (dirty, file) → update vm. Also handles delete/move.
    private func handleFileEvent(noteID: UUID) {
        if suppressedNotes.contains(noteID) { return }   // ⬆️ self-write suppression window
        guard let note = store.notes.first(where: { $0.id == noteID }),
              let controller = controllers[noteID] else { return }
        // Move tracking: resolve the current path via bookmark. If there's none or the file is gone, treat it as a delete (FileWatcher already debounced).
        guard let url = resolveSourceURL(note: note), FileManager.default.fileExists(atPath: url.path) else {
            handleDeletedFile(noteID: noteID)
            return
        }
        // If the path changed (same-volume move), update sourcePath and bookmark, then re-arm the watcher
        if url.path != note.sourcePath {
            store.setSourcePath(id: noteID, path: url.path, bookmark: try? url.bookmarkData())
            fileWatcher.watch(noteID: noteID, url: url) { [weak self] in self?.handleFileEvent(noteID: noteID) }
        }
        let gen = readGen.begin(noteID)   // generation token for this read; on completion, check it's still the latest
        readLinkedFile(url) { [weak self] result in
            guard let self else { return }
            guard self.readGen.isCurrent(noteID, gen) else { return }   // a newer read started after this one → discard (avoid getting stuck on stale data)
            guard let result else { return }   // read/decode failed → no-op (no auto-apply, M2)
            guard let note = self.store.notes.first(where: { $0.id == noteID }) else { return }
            let stickerHash = ContentHash.sha256Hex(note.content)
            switch decideSyncAction(stickerHash: stickerHash, fileHash: result.hash,
                                    syncedHash: note.syncedHash, isEditing: controller.vm.isEditing) {
            case .ignore:
                break
            case .converged:
                self.store.setSyncedHash(id: noteID, hash: result.hash)
                controller.vm.syncedHash = result.hash   // baseline moved → keep `diverged` (⬆️ enablement) accurate
                controller.vm.syncBanner = nil   // content converged with the file → clear any lingering conflict banner
            case .autoApply:
                switch self.store.applyFileSync(id: noteID, content: result.content, hash: result.hash) {
                case .success:
                    controller.vm.content = result.content
                    controller.vm.syncedHash = result.hash   // content and baseline both = file → not diverged
                    controller.vm.oversize = false
                    controller.vm.autoSyncPulse.toggle()
                case .failure(.contentTooLarge):
                    controller.vm.oversize = true   // persistent indicator, not a notification storm
                case .failure:
                    break
                }
            case .conflict:
                controller.vm.syncBanner = .conflict
            }
        }
    }

    /// Linked file deleted (still absent after debounce and resolve) → "keep (detach) / close" dialog.
    private func handleDeletedFile(noteID: UUID) {
        guard let note = store.notes.first(where: { $0.id == noteID }) else { return }
        let name = (note.sourcePath as NSString?)?.lastPathComponent ?? L10n.unnamedFile()
        let alert = NSAlert()
        alert.messageText = L10n.linkedFileNotFound()
        alert.informativeText = L10n.linkedFileMissingBody(name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.keepDetach())
        alert.addButton(withTitle: L10n.close())
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            detachNote(id: noteID)          // keep → detach (content preserved)
        } else {
            controllers[noteID]?.close()    // close → remove (close goes through unwatch)
        }
    }

    /// Detach: stop watching, remove link metadata (content preserved), reflect in vm (hide 🔗/⬆️).
    /// No-op on an already-standalone note so an unconditionally-wired onDetach can't churn (spurious save/vm writes).
    func detachNote(id: UUID) {
        guard store.notes.first(where: { $0.id == id })?.sourcePath != nil else { return }
        fileWatcher.unwatch(noteID: id)
        store.detachFromFile(id: id)
        controllers[id]?.vm.isLinked = false
        controllers[id]?.vm.syncedHash = nil   // hygiene: clear the baseline too (button is isLinked-gated, but keep vm consistent)
        controllers[id]?.vm.syncBanner = nil
        controllers[id]?.vm.oversize = false
    }
    /// Reveal the source in Finder.
    func revealNoteInFinder(id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }), let url = resolveSourceURL(note: note) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    /// Open the source in the default editor: the "edit in source" path.
    func openNoteInEditor(id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }), let url = resolveSourceURL(note: note) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Conflict banner "take file content": force-load the file version (discard sticker edits), clear the banner.
    func takeFileForNote(id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }),
              let controller = controllers[id],
              let url = resolveSourceURL(note: note) else { return }
        // Join the generation scheme: begin invalidates in-flight stale auto-reads, and take itself
        // joins latest-wins too, so a stale auto-read arriving late won't clobber the user's "take file".
        let gen = readGen.begin(id)
        readLinkedFile(url) { [weak self] result in
            guard let self else { return }
            defer { controller.vm.syncBanner = nil }   // explicit user action: always clear the banner
            guard self.readGen.isCurrent(id, gen) else { return }   // a newer read won → discard this stale take
            guard let result else { return }   // on read failure, just close the banner and no-op
            switch self.store.applyFileSync(id: id, content: result.content, hash: result.hash) {
            case .success:
                controller.vm.content = result.content
                controller.vm.syncedHash = result.hash   // took the file → content and baseline both = file → not diverged
                controller.vm.oversize = false
            case .failure(.contentTooLarge):
                controller.vm.oversize = true
            case .failure:
                break
            }
        }
    }

    /// Read the file off-main as UTF-8 and call back on main with (content, hash). nil on failure (no auto-apply).
    func readLinkedFile(_ url: URL, completion: @escaping ((content: String, hash: String)?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result: (String, String)? = (try? String(contentsOf: url, encoding: .utf8))
                .map { ($0, ContentHash.sha256Hex($0)) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Hide all stickers from the screen (non-destructive: notes and controllers are kept). Called from the menu bar.
    func hideAllStickers() { controllers.values.forEach { $0.hide() } }
    /// Bring all hidden stickers back to the front.
    func showAllStickers() { controllers.values.forEach { $0.show() } }

    // MARK: Convenience features Phase 1: clipboard, open file, export

    /// Create an empty sticker and drop straight into edit mode so the user can type. Menu bar "New blank sticker".
    func createBlankSticky() { createSticky(content: "", startEditing: true) }

    /// Create a standalone sticker from clipboard text. Menu bar "New sticker from clipboard".
    func createStickyFromClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reportError(L10n.clipboardEmpty())
            return
        }
        createSticky(content: raw)   // the content byte cap is enforced by store.add() (single source)
    }

    /// Pick a .md via NSOpenPanel → turn its content into a sticker. Store link metadata (sourcePath/bookmark), but
    /// Phase 1 leaves the sticker standalone (editable). Read-only and Live Sync come in Phase 2.
    func openMarkdownFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // Allow .md / .markdown / plain text (.txt isn't clearly markdown, but allow it for text viewing)
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "markdown") { types.insert(markdown, at: 0) }
        if let md = UTType(filenameExtension: "md") { types.insert(md, at: 0) }
        panel.allowedContentTypes = types
        NSApp.activate()   // accessory (LSUIElement) app: bring the panel to the front
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reportOpenFailure(openFile(at: url), url.lastPathComponent)
    }

    /// Among files dropped on the menu bar icon, open only .md/.markdown as stickers (drag-and-drop).
    /// The view (FileDropView) already applies an extension filter, but filter once more defensively at the entry point.
    func openDroppedFiles(_ urls: [URL]) {
        let exts: Set<String> = ["md", "markdown"]
        let mdURLs = urls.filter { exts.contains($0.pathExtension.lowercased()) }
        guard !mdURLs.isEmpty else {
            reportError(L10n.onlyMarkdown())
            return
        }
        // Multi-drop: instead of one notification per file, group failures by type and report up to 3 aggregates (avoid a notification storm).
        var capHit = false
        var tooLarge: [String] = []
        var readFail: [String] = []
        for url in mdURLs {
            switch openFile(at: url) {
            case .ok: break
            case .capReached: capHit = true
            case .tooLarge: tooLarge.append(url.lastPathComponent)
            case .readFailed: readFail.append(url.lastPathComponent)
            }
        }
        if capHit { reportError(L10n.capReachedSomeFiles(StickyStore.maxStickies)) }
        if !tooLarge.isEmpty { reportError(L10n.filesTooLarge(tooLarge.joined(separator: ", "))) }
        if !readFail.isEmpty { reportError(L10n.unreadableFiles(readFail.joined(separator: ", "))) }
    }

    /// openFile result: the caller decides how to report (single = immediate, multi-drop = aggregate).
    private enum OpenOutcome { case ok, readFailed, capReached, tooLarge }

    @discardableResult
    private func openFile(at url: URL) -> OpenOutcome {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return .readFailed
        }
        // Phase 1: store a plain bookmark (works outside the sandbox). When Phase 2 moves to the sandbox,
        // promote to a security-scoped bookmark (.withSecurityScope) and wire up FileWatcher.
        let bookmark = try? url.bookmarkData()
        switch store.add(content: content, sourcePath: url.path, sourceBookmark: bookmark) {
        case .success(let note):
            // Seed syncedHash at open time: establish a baseline before arming the watch.
            // Without it, the first external change causes a bogus banner and a false ⬆️ (regression).
            store.setSyncedHash(id: note.id, hash: ContentHash.sha256Hex(content))
            addController(for: note)
            return .ok
        case .failure(.capReached):
            return .capReached
        case .failure(.contentTooLarge):
            return .tooLarge
        case .failure(.noteNotFound):
            return .ok   // add never returns this error (defensive, to make the switch exhaustive)
        }
    }

    /// Report a single-file open failure immediately, one notification (panel path).
    private func reportOpenFailure(_ outcome: OpenOutcome, _ name: String) {
        switch outcome {
        case .ok: break
        case .readFailed: reportError(L10n.couldNotReadFile(name))
        case .capReached: reportError(L10n.maxStickiesReached(StickyStore.maxStickies))
        case .tooLarge: reportError(L10n.fileTooLargeMB())
        }
    }

    /// Manually push a linked sticker's current content to its source .md file (explicit user action).
    /// Not two-way auto-sync: only on button press, a one-way sticker→file write, so
    /// it's the sole writer at that moment and avoids conflicts. Independent of Live Sync (file→sticker, Phase 2).
    /// Returns true on success so the caller (sticker button) can give instant visual feedback (check/X). Failures notify in detail via reportError.
    @discardableResult
    func saveNoteToSourceFile(id: UUID) -> Bool {
        guard let note = store.notes.first(where: { $0.id == id }), note.sourcePath != nil else { return false }
        guard let resolved = resolveSourceURL(note: note) else {
            reportError(L10n.sourceNotFound())
            return false
        }
        // Resolve symlinks to the real target before writing: prevents atomically:true's rename from replacing
        // the link with a regular file and breaking the vault's symlink structure (review B Major).
        let url = resolved.resolvingSymlinksInPath()

        // Conflict detection (hash-based): if the current file content hash != syncedHash, it changed externally → confirmation dialog.
        // If syncedHash==nil (not seeded), skip detection (mirrors the Phase 1 mtime-nil guard; without it, the first ⬆️ triggers a bogus dialog, a regression).
        if let baseline = note.syncedHash,
           let fileContent = try? String(contentsOf: url, encoding: .utf8),
           ContentHash.sha256Hex(fileContent) != baseline {
            guard confirmOverwrite(fileName: url.lastPathComponent) else { return false }
        }

        do {
            try note.content.write(to: url, atomically: true, encoding: .utf8)
            // Ordering guarantee: update syncedHash synchronously right after the write → the incoming watcher callback sees F=false and ignores it.
            let newHash = ContentHash.sha256Hex(note.content)
            store.setSyncedHash(id: id, hash: newHash)
            controllers[id]?.vm.syncedHash = newHash   // pushed to file → baseline = content → not diverged (⬆️ greys)
            // self-write suppression window (second line of defense): prevents a bogus banner even if the user types during the re-arm window.
            suppressedNotes.insert(id)
            // ⚠️ Invariant: this suppression window (0.3s) must be larger than the FileWatcher re-arm + onChange cycle (0.15s)
            // so the atomic-save's self-write is absorbed within suppression. Change only one of them and the bogus banner regresses.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.suppressedNotes.remove(id) }
            return true
        } catch {
            reportError(L10n.couldNotSaveToSource(url.lastPathComponent))
            return false
        }
    }

    /// Overwrite confirmation shown only when the source changed externally. Returns true only if the user picks "Overwrite".
    private func confirmOverwrite(fileName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.sourceChangedExternally()
        alert.informativeText = L10n.overwriteBody(fileName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.overwrite())
        alert.addButton(withTitle: L10n.cancel())
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Resolve the current path via bookmark (tracks file moves). Falls back to the sourcePath string on failure.
    /// (Regenerating and re-saving a stale bookmark is Phase 2; impact is low with plain bookmarks for now.)
    private func resolveSourceURL(note: StickyNote) -> URL? {
        if let data = note.sourceBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        if let path = note.sourcePath { return URL(fileURLWithPath: path) }
        return nil
    }

    /// Save the sticker body as .md. Menu bar "Export sticker ▸ <note>".
    func exportNote(id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        if let md = UTType(filenameExtension: "md") { panel.allowedContentTypes = [md] }
        panel.nameFieldStringValue = ExportNaming.filename(for: note.content)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try note.content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            reportError(L10n.exportFailed(url.lastPathComponent))
        }
    }

    /// Save a standalone sticker to a new .md and link the sticker to it (the inverse of detachNote):
    /// write file → store.linkToFile (seeds syncedHash) → flip vm.isLinked → arm the Live Sync watch.
    /// After this the sticker gains the ⬆️/🔗 chrome and two-way sync, same as one opened from a file.
    /// Sticker button "Save to file…" (unlinked stickers only).
    func saveNoteToNewFile(id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        if let md = UTType(filenameExtension: "md") { panel.allowedContentTypes = [md] }
        panel.nameFieldStringValue = ExportNaming.filename(for: note.content)
        NSApp.activate()   // accessory app: bring the save panel to the front (same as export/open)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Resolve symlinks before writing so atomically:true's rename can't replace a vault symlink with a regular file (mirrors saveNoteToSourceFile).
        let target = url.resolvingSymlinksInPath()
        do {
            try note.content.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            reportError(L10n.saveToNewFileFailed(target.lastPathComponent))
            return
        }
        // Link only after a successful write. Seed syncedHash with the just-written content BEFORE arming the watch,
        // so the write's own file-watch event is ignored (self-write == baseline → decideSyncAction returns .ignore)
        // rather than raising a spurious conflict banner.
        let bookmark = try? target.bookmarkData()
        store.linkToFile(id: id, sourcePath: target.path, sourceBookmark: bookmark,
                         syncedHash: ContentHash.sha256Hex(note.content))
        controllers[id]?.vm.isLinked = true   // reactively reveals ⬆️/🔗 and hides "Save to file…"
        fileWatcher.watch(noteID: id, url: target) { [weak self] in self?.handleFileEvent(noteID: id) }
    }

    /// No silent failures: try a notification and always append to the menu bar's recent errors (permission-independent fallback)
    func reportError(_ message: String) {
        recentErrors = Array((recentErrors + [message]).suffix(5))
        let content = UNMutableNotificationContent()
        content.title = "post-md"
        content.body = message
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        ) { error in
            if let error { NSLog("post-md notification add failed: %@", "\(error)") }  // no silent failures
        }
        NSLog("post-md error: %@", message)
        statusMenu?.indicateError()  // fallback: even if the notification isn't visible, flag it via the menu bar icon badge
    }

    /// Self-check that this app is the post-md:// handler. Compare by bundleIdentifier (robust against symlinks),
    /// treat nil (handler unregistered) as an error too, and only run in a .app bundle (avoids a swift run false positive).
    /// Checks once at app launch (not per URL), which also catches handler hijacking on a later launch.
    private func verifySchemeHandler() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let probe = URL(string: "post-md://new") else { return }
        let myID = Bundle.main.bundleIdentifier
        guard let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: probe) else {
            reportError(L10n.handlerNotRegistered())
            return
        }
        if Bundle(url: handlerURL)?.bundleIdentifier != myID {
            reportError(L10n.handlerNotThisApp(handlerURL.lastPathComponent))
        }
    }

    private func errorMessage(for error: StickyURLError) -> String {
        switch error {
        case .unknownHost: return L10n.urlUnknownHost()
        case .missingContent: return L10n.urlMissingContent()
        case .invalidEncoding: return L10n.urlInvalidEncoding()
        }
    }
}
