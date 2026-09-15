// PostMDCore: target anchor

import Foundation

/// Builds the export filename. Pure logic, so it's unit tested. Kept outside AppKit (NSSavePanel).
public enum ExportNaming {
    /// Makes a safe .md filename from the sticker body.
    /// - Takes the first line as the title, stripping leading `#` and spaces
    /// - Replaces filename-illegal characters (`/ : \ ? % * | " < >`) with `-`
    /// - Truncates to 40 chars, falls back to "sticker" when empty
    public static func filename(for content: String) -> String {
        let firstLine = content.split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let stripped = firstLine.drop(while: { $0 == "#" || $0 == " " })
        let base = String(stripped).trimmingCharacters(in: .whitespaces)
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let safe = base.components(separatedBy: illegal).joined(separator: "-")
        let clipped = String(safe.prefix(40)).trimmingCharacters(in: .whitespaces)
        return clipped.isEmpty ? "sticker.md" : "\(clipped).md"
    }
}
