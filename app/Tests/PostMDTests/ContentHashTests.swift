import XCTest
@testable import PostMDCore

final class ContentHashTests: XCTestCase {
    func testKnownVector() {
        // SHA-256 of "abc" (known vector)
        XCTAssertEqual(ContentHash.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testEmpty() {
        XCTAssertEqual(ContentHash.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
    func testStableAcrossCalls() {
        let a = ContentHash.sha256Hex("안녕🎉 markdown\n# heading")
        let b = ContentHash.sha256Hex("안녕🎉 markdown\n# heading")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
    }
    func testDiffersByOneByte() {
        XCTAssertNotEqual(ContentHash.sha256Hex("a"), ContentHash.sha256Hex("a\n"))
    }
}
