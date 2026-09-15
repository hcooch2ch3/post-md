import SwiftUI
import MarkdownUI
import PostMDCore

struct StickyContentView: View {
    @ObservedObject var vm: StickyViewModel     // reactive content, banner, edit state
    let initialOpacity: Double
    let initialPinned: Bool
    let startEditing: Bool                       // blank-create: auto-enter edit mode on first appear
    let onClose: () -> Void
    let onTogglePin: (Bool) -> Void
    let onOpacityChange: (Double) -> Void
    let onOpacityCommit: (Double) -> Void
    let onContentChange: ((String) -> Bool)?   // inline-edit save callback. Returns success (on failure, keeps editing). nil disables editing.
    let onSaveToFile: (() -> Bool)?             // push current content back to the source file (linked stickers only). Returns success.
    let onSaveToNewFile: (() -> Void)?          // standalone sticker: save to a new .md file and link to it (unlinked stickers only)
    let onDetach: (() -> Void)?                 // unlink (🔗 popover)
    let onRevealInFinder: (() -> Void)?         // reveal in Finder
    let onOpenInEditor: (() -> Void)?           // open in the source editor
    let onColorChange: ((String?) -> Void)?     // change sticky-note color (nil = default)
    let onTakeFile: (() -> Void)?               // conflict banner "pull file content" (linked stickers only)

    @Environment(\.colorScheme) private var systemColorScheme
    @State private var hovering = false
    @State private var opacity: Double
    @State private var pinned: Bool
    // inline editing (S1 spike: verify TextEditor key input in a nonactivating panel)
    @State private var isEditing = false
    // read-mode render source is vm.content (reactive). When Live Sync updates vm.content it re-renders at once.
    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool
    // instant feedback on "save to source": green check on success, red X on failure, reverts after ~1.2s
    private enum SaveFlash { case success, failure }
    @State private var saveFlash: SaveFlash? = nil
    // sticky-note color: swatch popover plus current selection (key is persisted via callback, applied instantly via @State)
    @State private var colorKey: String?
    @State private var showColorPicker = false
    @State private var pulseVisible = false      // brief top highlight on clean auto-sync
    @State private var showLinkPopover = false    // 🔗 link info / unlink popover
    @State private var didAutoEdit = false        // blank-create: fire startEditing auto-entry once (onAppear can repeat)

    init(vm: StickyViewModel, initialOpacity: Double, initialPinned: Bool,
         startEditing: Bool = false,
         onClose: @escaping () -> Void,
         onTogglePin: @escaping (Bool) -> Void,
         onOpacityChange: @escaping (Double) -> Void,
         onOpacityCommit: @escaping (Double) -> Void,
         onContentChange: ((String) -> Bool)? = nil,
         onSaveToFile: (() -> Bool)? = nil,
         initialColor: String? = nil,
         onColorChange: ((String?) -> Void)? = nil,
         onTakeFile: (() -> Void)? = nil,
         onDetach: (() -> Void)? = nil,
         onRevealInFinder: (() -> Void)? = nil,
         onOpenInEditor: (() -> Void)? = nil,
         onSaveToNewFile: (() -> Void)? = nil) {
        _vm = ObservedObject(wrappedValue: vm)
        self.initialOpacity = initialOpacity
        self.initialPinned = initialPinned
        self.startEditing = startEditing
        self.onClose = onClose
        self.onTogglePin = onTogglePin
        self.onOpacityChange = onOpacityChange
        self.onOpacityCommit = onOpacityCommit
        self.onContentChange = onContentChange
        self.onSaveToFile = onSaveToFile
        self.onSaveToNewFile = onSaveToNewFile
        self.onDetach = onDetach
        self.onRevealInFinder = onRevealInFinder
        self.onOpenInEditor = onOpenInEditor
        self.onColorChange = onColorChange
        self.onTakeFile = onTakeFile
        _colorKey = State(initialValue: initialColor)
        _opacity = State(initialValue: initialOpacity)
        _pinned = State(initialValue: initialPinned)
    }

    private func beginEdit() {
        guard onContentChange != nil else { return }   // editing-disabled sticker
        draft = vm.content
        isEditing = true
        vm.setEditing(true)   // makes Live Sync treat this as dirty (prevents clobbering uncommitted edits)
        // Focus is driven by the TextEditor's own .onAppear (focusEditor): the field is guaranteed to be in the
        // view tree there. The old same-tick/next-tick async guess couldn't guarantee that on a blank-create cold
        // start (order-front + programmatic make-key + first layout + mount all in one runloop), dropping the focus.
    }

    /// Focus the editor with a bounded retry. Called from the TextEditor's .onAppear. On a cold-start create the
    /// panel may not be key/first-responder on the first attempt, so re-assert a few times until @FocusState takes.
    private func focusEditor(attempt: Int = 0) {
        editorFocused = true
        guard attempt < 5 else { return }   // ~5 × 50ms ceiling; stop once focus took or we've tried enough
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if isEditing, !editorFocused { focusEditor(attempt: attempt + 1) }
        }
    }
    @discardableResult
    private func commitEdit() -> Bool {
        // on save failure (e.g. over 1MB), stay in edit mode and don't update vm.content (controller shows the error).
        // no silent failures: don't let an edit vanish without a trace.
        let ok = onContentChange?(draft) ?? true
        guard ok else { return false }
        vm.content = draft
        isEditing = false
        vm.setEditing(false)
        // Auto write-back: a linked sticker whose content now differs from the file pushes to the source file,
        // reusing the ⬆️ path (incl. the confirmOverwrite dialog on external change). Skipped when in sync, so a
        // no-op edit doesn't touch the file. onContentChange already persisted `draft` to the store, which is
        // what onSaveToFile reads. (Unlinked stickers skip this; the Save-to-file flow below links them instead.)
        if vm.isLinked, vm.diverged, let onSaveToFile {
            flashSaveResult(onSaveToFile())
        }
        return true
    }
    /// Edit-toolbar "Save to file…": commit the in-progress draft first so the file gets the typed content, then save+link.
    private func commitThenSaveToNewFile() {
        guard commitEdit() else { return }   // abort save if the commit failed (e.g. over 1MB)
        onSaveToNewFile?()
    }
    private func cancelEdit() {
        isEditing = false   // discard draft
        vm.setEditing(false)
    }

    // icon/color for the "save to source" button: ⬆️ at rest, ✓ (green) on success, ✗ (red) on failure
    private var saveIconName: String {
        switch saveFlash {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case nil:      return "arrow.up.doc"
        }
    }
    // extracted from the top chrome HStack to keep that expression within the SwiftUI type-checker's budget.
    @ViewBuilder private var saveToNewFileChromeButton: some View {
        if !vm.isLinked, let onSaveToNewFile, !isEditing {
            Button(action: onSaveToNewFile) {
                Image(systemName: "arrow.down.doc").imageScale(.medium).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.saveToNewFile())
            .help(L10n.saveToNewFile())
        }
    }
    private var saveIconColor: Color {
        switch saveFlash {
        case .success: return .green
        case .failure: return .red
        case nil:      return .secondary
        }
    }
    // a single color swatch: on selection, apply instantly, persist via callback, and close the popover. key=nil means "default".
    @ViewBuilder
    private func colorSwatch(key: String?, color: Color?) -> some View {
        let isSelected = (key == colorKey)
        Button(action: {
            colorKey = key
            onColorChange?(key)
            showColorPicker = false
        }) {
            Circle()
                .fill(color ?? Color(nsColor: .windowBackgroundColor))
                .frame(width: 20, height: 20)
                .overlay {   // default (no color) shows a slash
                    if color == nil {
                        Image(systemName: "line.diagonal")
                            .imageScale(.small).foregroundStyle(.secondary)
                    }
                }
                .overlay {   // selection-indicator border
                    Circle().strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                                          lineWidth: isSelected ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(StickyPalette(rawValue: key ?? "")?.label ?? L10n.defaultColorLabel())
    }

    private func flashSaveResult(_ ok: Bool) {
        withAnimation { saveFlash = ok ? .success : .failure }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { saveFlash = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // top chrome bar, always visible (darkens on hover). Left: close, pin / center: opacity / right: edit, save
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.closeSticker())

                Button(action: { pinned.toggle(); onTogglePin(pinned) }) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .imageScale(.medium)
                        .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pinned ? L10n.unpin() : L10n.pin())

                // color: swatch popover (sticky-note presets)
                if onColorChange != nil {
                    Button(action: { showColorPicker.toggle() }) {
                        Image(systemName: "paintpalette")
                            .imageScale(.medium)
                            .foregroundStyle(StickyPalette.color(forKey: colorKey) != nil ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.color())
                    .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                        HStack(spacing: 8) {
                            colorSwatch(key: nil, color: nil)   // default
                            ForEach(StickyPalette.allCases) { colorSwatch(key: $0.rawValue, color: $0.color) }
                        }
                        .padding(10)
                    }
                }

                Spacer(minLength: 4)
                // opacity: before the right-side buttons, fixed narrow (moved from the bottom bar to the top). Width capped so it doesn't dominate.
                Image(systemName: "circle.lefthalf.filled")
                    .imageScale(.small).foregroundStyle(.secondary)
                Slider(value: $opacity, in: 0.3...1.0) { editing in
                    if !editing { onOpacityCommit(opacity) }
                }
                .onChange(of: opacity) { _, v in onOpacityChange(v) }
                .controlSize(.mini)
                .frame(width: 70)
                .accessibilityLabel(L10n.opacity())

                // edit button: editable stickers only (onContentChange != nil). Alternate entry point to double-click
                if onContentChange != nil, !isEditing {
                    Button(action: beginEdit) {
                        Image(systemName: "pencil").imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.edit())
                }
                // save to a new file + link: standalone (unlinked) stickers only. Once linked, the ⬆️ button below takes over.
                saveToNewFileChromeButton
                // 🔗 link indicator / popover: file-linked stickers only
                if vm.isLinked, !isEditing {
                    Button(action: { showLinkPopover.toggle() }) {
                        Image(systemName: "link").imageScale(.medium).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.fileLink())
                    .popover(isPresented: $showLinkPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button(L10n.showInFinder()) { showLinkPopover = false; onRevealInFinder?() }
                            Button(L10n.openInEditor()) { showLinkPopover = false; onOpenInEditor?() }
                            Divider()
                            Button(L10n.detach()) { showLinkPopover = false; onDetach?() }
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                }
                // save to source: file-linked stickers only. Push edits back to the source .md, with visual result feedback.
                if vm.isLinked, let onSaveToFile, !isEditing {
                    Button(action: { flashSaveResult(onSaveToFile()) }) {
                        Image(systemName: saveIconName)
                            .imageScale(.medium)
                            .foregroundStyle(saveIconColor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .disabled(saveFlash != nil || !vm.diverged)   // greyed when the sticker matches the file (nothing to push)
                    .accessibilityLabel(saveFlash == .success ? L10n.saved() : L10n.saveToSourceFile())
                    .help(L10n.saveToSourceFile())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.thinMaterial.opacity(hovering ? 1.0 : 0.55))

            // conflict banner: shown when both sides changed. Sits above the edit UI (edits kept). Default is to ignore = non-destructive.
            if vm.syncBanner == .conflict {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(L10n.bothChanged()).font(.caption)
                    Spacer(minLength: 4)
                    Button(L10n.takeFile()) { onTakeFile?() }
                    Button(L10n.keepMyEdits()) { vm.syncBanner = nil }
                }
                .controlSize(.small)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.yellow.opacity(0.18))
            }
            // file-oversize indicator: persistent (not a repeating toast)
            if vm.oversize {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                    Text(L10n.linkedFileTooLarge()).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
            }

            // body: read (Markdown) ↔ edit (TextEditor)
            if isEditing {
                VStack(spacing: 4) {
                    TextEditor(text: $draft)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .focused($editorFocused)
                        .onExitCommand(perform: cancelEdit)   // Esc → cancel
                        .onAppear { focusEditor() }           // grab focus once the field is actually in the tree (reliable on cold-start create)
                    HStack(spacing: 8) {
                        // standalone sticker: save the typed content to a new .md and link to it (visible right while typing a fresh sticky)
                        if !vm.isLinked, onSaveToNewFile != nil {
                            Button(L10n.saveToNewFile(), action: commitThenSaveToNewFile)
                        }
                        Spacer()
                        Button(L10n.cancel(), action: cancelEdit)
                            .keyboardShortcut(.cancelAction)
                        Button(L10n.save()) { commitEdit() }
                            .keyboardShortcut(.return, modifiers: .command)   // ⌘Enter → save
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 8).padding(.bottom, 6)
                }
            } else {
                ScrollView {
                    Markdown(vm.content)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: beginEdit)   // double-click → edit
            }
        }
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(StickyPalette.color(forKey: colorKey) ?? Color(nsColor: .windowBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // with a color (light pastel), force the light appearance so text stays black and chrome stays consistently light. Default keeps the system appearance.
        .environment(\.colorScheme, colorKey != nil ? .light : systemColorScheme)
        .overlay(alignment: .top) {   // auto-sync flash (autoSyncPulse)
            Rectangle().fill(Color.accentColor).frame(height: 2)
                .opacity(pulseVisible ? 1 : 0)
        }
        .onChange(of: vm.autoSyncPulse) { _, _ in
            pulseVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation { pulseVisible = false }
            }
        }
        .onAppear {   // blank-create: enter edit mode once. onAppear can fire again (Space switch, re-mount) → guard.
            guard startEditing, !didAutoEdit else { return }
            didAutoEdit = true
            beginEdit()   // isEditing → TextEditor mounts → its .onAppear (focusEditor) grabs focus
        }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
