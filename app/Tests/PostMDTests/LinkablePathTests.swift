import XCTest
@testable import PostMDCore

final class LinkablePathTests: XCTestCase {
    private func tempFile(ext: String, name: String = "note") -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("\(name)-\(UUID().uuidString).\(ext)")
        try? "hi".write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testAcceptsExistingMarkdownFile() {
        let path = tempFile(ext: "md")
        // resolvingSymlinksInPath may canonicalize /var → /private/var on macOS, so compare resolved forms
        XCTAssertEqual(LinkablePath.validate(path)?.path, URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }
    func testAcceptsMarkdownAndTxtExtensions() {
        XCTAssertNotNil(LinkablePath.validate(tempFile(ext: "markdown")))
        XCTAssertNotNil(LinkablePath.validate(tempFile(ext: "txt")))
    }
    func testRejectsDisallowedExtension() {
        XCTAssertNil(LinkablePath.validate(tempFile(ext: "png")))
    }
    func testRejectsMissingFile() {
        XCTAssertNil(LinkablePath.validate("/nope/\(UUID().uuidString).md"))
    }
    func testRejectsDirectory() {
        XCTAssertNil(LinkablePath.validate(FileManager.default.temporaryDirectory.path))
    }
    func testRejectsNonRegularSpecialFile() {
        // A FIFO with an allowed extension must be rejected — the guard requires a REGULAR file,
        // not just a non-directory (fileExists(isDirectory:) alone would let this through).
        let dir = FileManager.default.temporaryDirectory
        let fifo = dir.appendingPathComponent("f-\(UUID().uuidString).md")
        guard mkfifo(fifo.path, 0o644) == 0 else { return XCTFail("mkfifo failed") }
        defer { try? FileManager.default.removeItem(at: fifo) }
        XCTAssertNil(LinkablePath.validate(fifo.path))
    }
    func testResolvesSymlinkAndValidatesTarget() {
        // A `.md` symlink whose target is a disallowed type must be rejected — the extension is
        // checked on the resolved target, not the link name.
        let dir = FileManager.default.temporaryDirectory
        let target = dir.appendingPathComponent("t-\(UUID().uuidString).png")
        try? "x".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("l-\(UUID().uuidString).md")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertNil(LinkablePath.validate(link.path))
    }
}
