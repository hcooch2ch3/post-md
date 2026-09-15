import Foundation

/// Receiver-side guard for a path handed in via `sticky://open?path=`. A URL can be fired by any app or
/// web page, so we only ever open an existing regular file with a markdown/text extension — never a
/// directory, a missing path, or an arbitrary system file.
public enum LinkablePath {
    public static let allowedExtensions: Set<String> = ["md", "markdown", "txt"]

    public static func validate(_ path: String, fileManager: FileManager = .default) -> URL? {
        // Resolve symlinks BEFORE the extension/type checks: openFile reads via String(contentsOf:), which
        // follows symlinks, so a `.md` symlink pointing at a non-allowlisted target would otherwise slip past.
        // (The write-back path already resolves symlinks in AppDelegate; the read/guard path must too.)
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        // Must be a REGULAR file — not a directory, FIFO, socket, or device. fileExists(isDirectory:)
        // only rules out directories, so a special file with an allowed extension would otherwise slip through.
        guard let type = try? url.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType,
              type == .regular else { return nil }
        return url
    }
}
