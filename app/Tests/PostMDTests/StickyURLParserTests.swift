import XCTest
@testable import PostMDCore

final class StickyURLParserTests: XCTestCase {
    // Shared golden vectors, all 3 (now wrapped in the action enum)
    func testGoldenVector_KoreanEmoji() {
        let url = URL(string: "sticky://new?content=7JWI64WV8J-OiQ")!
        XCTAssertEqual(StickyURLParser.parse(url), .success(.new(content: "안녕🎉")))
    }
    func testGoldenVector_ASCII() {
        let url = URL(string: "sticky://new?content=aGk")!
        XCTAssertEqual(StickyURLParser.parse(url), .success(.new(content: "hi")))
    }
    func testGoldenVector_Underscore() {
        // this vector contains '_' (the most fragile _→/ reverse-mapping path)
        let url = URL(string: "sticky://new?content=7J296riwPz8_")!
        XCTAssertEqual(StickyURLParser.parse(url), .success(.new(content: "읽기???")))
    }

    // host / path / fragment grammar
    func testUnknownHost() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://update?content=aGk")!), .failure(.unknownHost))
    }
    func testUppercaseHostRejected() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://NEW?content=aGk")!), .failure(.unknownHost))
    }
    func testNonEmptyPathRejected() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new/foo?content=aGk")!), .failure(.unknownHost))
    }
    func testTrailingSlashAllowed() {
        // treated as an empty path, so allowed
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new/?content=aGk")!), .success(.new(content: "hi")))
    }
    func testFragmentRejected() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=aGk#x")!), .failure(.unknownHost))
    }

    // content presence / empty value / duplicate
    func testMissingContent() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new")!), .failure(.missingContent))
    }
    func testEmptyContent() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=")!), .failure(.missingContent))
    }
    func testDuplicateContentRejected() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=aGk&content=YWI")!), .failure(.missingContent))
    }

    // scheme regression
    func testNonStickySchemeRejected() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "http://new?content=aGk")!), .failure(.unknownHost))
        XCTAssertEqual(StickyURLParser.parse(URL(string: "evil://new?content=aGk")!), .failure(.unknownHost))
    }

    // content alphabet / decode
    func testPercentEncodedContentRejected() {
        // a%47k: raw contains %. URLComponents decodes %47→G to yield aGk, but the raw check must reject it (contract: check before decoding)
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=a%47k")!), .failure(.invalidEncoding))
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=%61Gk")!), .failure(.invalidEncoding))
    }
    func testTrailingNewlineRejected() {
        // aGk%0A → raw "aGk%0A": the \A...\z anchors reject the newline percent-escape
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=aGk%0A")!), .failure(.invalidEncoding))
    }
    func testAlphabetViolation() {
        // %25%25%25 → "%%%" (not the base64url alphabet)
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=%25%25%25")!), .failure(.invalidEncoding))
    }
    func testInvalidUTF8Bytes() {
        // 0xFF 0xFE = valid base64url but not decodable as UTF-8 → "__4" (Data [0xFF,0xFE])
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=__4")!), .failure(.invalidEncoding))
    }

    // forward compatibility
    func testUnknownParamsIgnored() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://new?content=aGk&future=x")!), .success(.new(content: "hi")))
    }

    // --- open verb: sticky://open?path=<base64url absolute path> ---
    func testOpenVerb_DecodesAbsolutePath() {
        // toBase64URL("/Users/me/Notes/n.md")
        let url = URL(string: "sticky://open?path=L1VzZXJzL21lL05vdGVzL24ubWQ")!
        XCTAssertEqual(StickyURLParser.parse(url), .success(.open(path: "/Users/me/Notes/n.md")))
    }
    func testOpenVerb_RelativePathRejected() {
        // toBase64URL("notes/n.md") — decodes fine but has no leading slash → rejected
        let url = URL(string: "sticky://open?path=bm90ZXMvbi5tZA")!
        XCTAssertEqual(StickyURLParser.parse(url), .failure(.invalidEncoding))
    }
    func testOpenVerb_MissingPathParam() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://open")!), .failure(.missingContent))
    }
    func testOpenVerb_NonBase64PathRejected() {
        // raw value "/etc/passwd" contains '/', which fails the base64url alphabet check before decode
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://open?path=/etc/passwd")!), .failure(.invalidEncoding))
    }
    func testOpenVerb_UppercaseHostRejected() {
        XCTAssertEqual(StickyURLParser.parse(URL(string: "sticky://OPEN?path=L1VzZXJzL21lL05vdGVzL24ubWQ")!), .failure(.unknownHost))
    }
    func testOpenVerb_DuplicatePathRejected() {
        XCTAssertEqual(
            StickyURLParser.parse(URL(string: "sticky://open?path=L1VzZXJzL21lL05vdGVzL24ubWQ&path=L2E")!),
            .failure(.missingContent))
    }
}
