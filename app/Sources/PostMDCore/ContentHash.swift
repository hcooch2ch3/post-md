import Foundation
import CryptoKit

/// Stable SHA-256 hex of the content. String.hashValue reseeds every run, so it won't do. Uses CryptoKit.
public enum ContentHash {
    public static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
