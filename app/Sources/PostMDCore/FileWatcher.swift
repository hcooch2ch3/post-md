import Foundation

/// File watcher that survives atomic saves (temp+rename). Formalizes the S2 spike.
/// File fd DispatchSource, plus debounce then path recheck and re-arm on rename/delete.
/// Holds the security-scoped URL for the fd's whole lifetime (N1). Near-no-op unsandboxed, but the structure is there.
/// Thread contract: callbacks on the main queue. The caller (controller) is on main. Pure Foundation, so it lives in Core and gets unit tested.
public final class FileWatcher {
    private struct Watch { let source: DispatchSourceFileSystemObject; let scopedURL: URL; let accessing: Bool }
    private var watches: [UUID: Watch] = [:]
    // Holds the in-flight debounce re-arm so it can be cancelled: teardown/unwatch must
    // invalidate a scheduled re-arm, or detach/delete leaves a zombie watch revived, an fd leak, and a spurious dialog.
    private var rearmWork: [UUID: DispatchWorkItem] = [:]

    public init() {}

    /// Starts accessing the url (security-scope), then arms the fd watch. Replaces any existing watch.
    public func watch(noteID: UUID, url: URL, onChange: @escaping () -> Void) {
        unwatch(noteID: noteID)
        arm(noteID: noteID, url: url, onChange: onChange)
    }

    private func arm(noteID: UUID, url: URL, onChange: @escaping () -> Void) {
        let accessing = url.startAccessingSecurityScopedResource()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { if accessing { url.stopAccessingSecurityScopedResource() }; return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.handle(noteID: noteID, url: url, flags: src.data, onChange: onChange) }
        src.setCancelHandler { close(fd) }
        watches[noteID] = Watch(source: src, scopedURL: url, accessing: accessing)
        src.resume()
    }

    private func handle(noteID: UUID, url: URL, flags: DispatchSource.FileSystemEvent, onChange: @escaping () -> Void) {
        if flags.contains(.write) || flags.contains(.extend) { onChange() }
        if flags.contains(.delete) || flags.contains(.rename) {
            // atomic swap/rename: the current fd is stale, so stop-old atomically and re-arm after a debounce.
            // teardown cancels the prior schedule, so even a rapid rename leaves only the latest single schedule.
            teardown(noteID: noteID)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.rearmWork[noteID] = nil
                if FileManager.default.fileExists(atPath: url.path) {
                    self.arm(noteID: noteID, url: url, onChange: onChange)
                    onChange()   // re-arm = notify the decision logic of a file change (one unified "re-evaluate" ping)
                } else {
                    onChange()   // real delete: the decision logic rechecks, then handles the deletion
                }
            }
            rearmWork[noteID] = work
            // ⚠️ Invariant: this re-arm delay (0.15s) must stay below AppDelegate's self-write suppression window (0.3s),
            // so the atomic-save self-write refire lands inside the suppression window and no spurious banner shows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    public func unwatch(noteID: UUID) { teardown(noteID: noteID) }
    // Snapshot to avoid mutation while iterating. Union in rearmWork.keys too: a note just after a rename
    // (absent from watches but present in rearmWork) is mid-rearm and must also be cancelled, or the teardown path revives a zombie watch.
    public func unwatchAll() { Set(watches.keys).union(rearmWork.keys).forEach { teardown(noteID: $0) } }

    private func teardown(noteID: UUID) {
        rearmWork[noteID]?.cancel()   // invalidate the in-flight re-arm schedule: must run even when there's no watch
        rearmWork[noteID] = nil
        guard let w = watches.removeValue(forKey: noteID) else { return }
        w.source.cancel()
        if w.accessing { w.scopedURL.stopAccessingSecurityScopedResource() }
    }
}
