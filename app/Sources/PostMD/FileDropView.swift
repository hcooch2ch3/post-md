import AppKit

/// Drop target that opens `.md`/`.markdown` files dropped on the menu bar icon as stickers.
///
/// Sits over `statusItem.button` and receives drops only. Mouse clicks (opening the menu) pass through
/// to the button below via the default responder chain, with no extra override (drop reception confirmed in the S3 spike; clicks verified manually).
/// If any non-markdown file is in the mix, the drag-over is rejected outright (no highlight, no accept).
final class FileDropView: NSView {
    private let onDrop: ([URL]) -> Void
    private var highlighted = false { didSet { if oldValue != highlighted { needsDisplay = true } } }

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    // Let mouse events pass through this view so the statusItem.button below (opening the menu) receives them.
    // Drop-destination registration (registerForDraggedTypes) goes through the dragging-destination path, which
    // doesn't use hitTest, so drops are still received even when this returns nil → click pass-through is guaranteed regardless of macOS version.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !markdownURLs(sender).isEmpty else { return [] }   // no .md means no accept
        highlighted = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let urls = markdownURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    /// Extract only .md/.markdown URLs from the drop pasteboard (multiple files supported).
    private func markdownURLs(_ sender: NSDraggingInfo) -> [URL] {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let exts: Set<String> = ["md", "markdown"]
        return urls.filter { exts.contains($0.pathExtension.lowercased()) }
    }

    // Drag-over highlight (Step 2): a subtle rounded background behind the icon.
    override func draw(_ dirtyRect: NSRect) {
        guard highlighted else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
    }
}
