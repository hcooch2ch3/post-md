import XCTest
@testable import PostMDCore

final class ExportNamingTests: XCTestCase {
    func testUsesFirstLineStrippingMarkdownHeading() {
        XCTAssertEqual(ExportNaming.filename(for: "# 회의 메모\n본문..."), "회의 메모.md")
        XCTAssertEqual(ExportNaming.filename(for: "### 제목만"), "제목만.md")
    }

    func testPlainFirstLine() {
        XCTAssertEqual(ExportNaming.filename(for: "장보기 목록\n- 우유"), "장보기 목록.md")
    }

    func testEmptyOrWhitespaceFallsBackToSticker() {
        XCTAssertEqual(ExportNaming.filename(for: ""), "sticker.md")
        XCTAssertEqual(ExportNaming.filename(for: "   \n다음"), "sticker.md")
        XCTAssertEqual(ExportNaming.filename(for: "###   "), "sticker.md")
    }

    func testStripsIllegalFilenameCharacters() {
        XCTAssertEqual(ExportNaming.filename(for: "a/b:c?d"), "a-b-c-d.md")
    }

    func testClipsToFortyChars() {
        let long = String(repeating: "가", count: 60)
        let name = ExportNaming.filename(for: long)
        // "<40 chars>.md" → 40 + ".md"
        XCTAssertEqual(name, String(repeating: "가", count: 40) + ".md")
    }
}
