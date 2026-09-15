import Foundation

public enum StickyURLError: Error, Equatable {
    case unknownHost      // scheme != "sticky" / unknown host / non-empty path / fragment / parse failure
    case missingContent   // required query param (content|path) absent / empty / duplicate
    case invalidEncoding  // base64url or UTF-8 decode failure, or a non-absolute open path
}

/// The action a sticky:// URL requests.
public enum StickyURLAction: Equatable {
    case new(content: String)   // sticky://new?content=<base64url> — detached snapshot
    case open(path: String)     // sticky://open?path=<base64url abs path> — file-linked sticker
}

/// sticky:// URL parser. Pure logic, no AppKit.
/// Note: the raw URL length limit (receiver-side oversize) is decided by the AppDelegate that receives the URL, not this parser.
public enum StickyURLParser {
    // base64url (unpadded), whole-string anchored. NSRegularExpression's $ allows a trailing \n, so \z is used.
    private static let base64urlAlphabet = try! NSRegularExpression(pattern: "\\A[A-Za-z0-9_-]+\\z")

    public static func parse(_ url: URL) -> Result<StickyURLAction, StickyURLError> {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.unknownHost)  // collapse a parse failure into unknownHost (observed behavior matches the contract)
        }
        // scheme: lowercase "sticky" only. URLComponents doesn't lowercase custom-scheme host/scheme, so compare explicitly.
        guard comps.scheme == "sticky" else { return .failure(.unknownHost) }
        // path: only empty or "/" (a trailing slash) allowed
        guard comps.path.isEmpty || comps.path == "/" else { return .failure(.unknownHost) }
        // fragment: not allowed
        guard comps.fragment == nil else { return .failure(.unknownHost) }

        // host (case-sensitive): "new" → snapshot, "open" → file link
        switch comps.host {
        case "new":
            return decodeParam("content", from: comps).map { .new(content: $0) }
        case "open":
            return decodeParam("path", from: comps).flatMap { path in
                // Absolute paths only (defense in depth; the receiver also validates existence + file type).
                guard path.hasPrefix("/") else { return .failure(.invalidEncoding) }
                return .success(.open(path: path))
            }
        default:
            return .failure(.unknownHost)
        }
    }

    /// Extract exactly one query param by name and decode its unpadded-base64url value to a UTF-8 string.
    /// Reads the raw (percent-encoded) value so a %-escape can't smuggle a non-alphabet byte past the check
    /// (queryItems.value is already percent-decoded and would miss a bypass like %47 → G).
    private static func decodeParam(_ name: String, from comps: URLComponents) -> Result<String, StickyURLError> {
        // exactly 1 (reject duplicate, zero, empty)
        let items = (comps.percentEncodedQueryItems ?? []).filter { $0.name == name }
        guard items.count == 1, let raw = items[0].value, !raw.isEmpty else {
            return .failure(.missingContent)
        }
        // alphabet check (unpadded base64url): a % or newline in raw is rejected here
        let range = NSRange(raw.startIndex..., in: raw)
        guard base64urlAlphabet.firstMatch(in: raw, range: range) != nil else {
            return .failure(.invalidEncoding)
        }
        // base64url → standard base64: reverse-map and re-pad (skip it and even valid input goes nil)
        var b64 = raw.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder > 0 { b64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: b64),
              let s = String(data: data, encoding: .utf8),
              !s.isEmpty else {
            return .failure(.invalidEncoding)
        }
        return .success(s)
    }
}
