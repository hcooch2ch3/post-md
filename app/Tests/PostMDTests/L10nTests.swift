import XCTest
@testable import PostMDCore

final class L10nTests: XCTestCase {
    private static let suiteName = "test.post-md.l10n"

    override func setUp() {
        super.setUp()
        // Isolate the override store so the test never touches the real UserDefaults.standard domain.
        let suite = UserDefaults(suiteName: Self.suiteName)!
        suite.removePersistentDomain(forName: Self.suiteName)
        L10n.store = suite
    }

    override func tearDown() {
        L10n.store.removePersistentDomain(forName: Self.suiteName)
        L10n.store = .standard
        super.tearDown()
    }

    // Pure detection seam: primary-subtag exact match, English fallback.
    func testLanguageDetection() {
        XCTAssertEqual(L10n.language(for: ["ko"]), .ko)
        XCTAssertEqual(L10n.language(for: ["ko-KR"]), .ko)
        XCTAssertEqual(L10n.language(for: ["en"]), .en)
        XCTAssertEqual(L10n.language(for: ["en-US"]), .en)
        XCTAssertEqual(L10n.language(for: ["fr"]), .en)
        XCTAssertEqual(L10n.language(for: ["kok"]), .en)   // Konkani must NOT map to Korean
        XCTAssertEqual(L10n.language(for: ["kos"]), .en)   // Kosraean must NOT map to Korean
        XCTAssertEqual(L10n.language(for: []), .en)
    }

    // Override short-circuits before touching the process locale; .system delegates to the seam.
    func testOverrideResolution() {
        L10n.override = .en
        XCTAssertEqual(L10n.current, .en)
        L10n.override = .ko
        XCTAssertEqual(L10n.current, .ko)
        // .system round-trips through the store and delegates to OS detection.
        L10n.override = .system
        XCTAssertEqual(L10n.override, .system)
        XCTAssertEqual(L10n.current, L10n.language(for: Locale.preferredLanguages))
    }

    // English pluralization actually branches on count.
    func testPluralization() {
        XCTAssertNotEqual(L10n.maxStickiesReached(1, .en), L10n.maxStickiesReached(5, .en))
        XCTAssertTrue(L10n.maxStickiesReached(1, .en).contains("1 sticker"))
        XCTAssertTrue(L10n.maxStickiesReached(5, .en).contains("5 stickers"))
    }

    // Both languages resolve, and a parameterized string interpolates.
    func testStringsResolve() {
        XCTAssertEqual(L10n.closeSticker(.en), "Close sticker")
        XCTAssertEqual(L10n.closeSticker(.ko), "스티커 닫기")
        XCTAssertEqual(L10n.colorAndOpacity(.en), "Color and opacity")
        XCTAssertEqual(L10n.colorAndOpacity(.ko), "색상과 투명도")
        XCTAssertTrue(L10n.linkedFileMissingBody("a.md", .en).contains("a.md"))
        XCTAssertTrue(L10n.linkedFileMissingBody("a.md", .ko).contains("a.md"))
    }

    // Size strings derive the MB number from the single source of truth (never hardcode "1MB").
    func testSizeStringsDeriveMB() {
        let mb = StickyStore.maxContentBytes / (1024 * 1024)
        XCTAssertTrue(L10n.contentTooLargeMB(.en).contains("\(mb)MB"))
        XCTAssertTrue(L10n.fileTooLargeMB(.ko).contains("\(mb)MB"))
        XCTAssertTrue(L10n.linkedFileTooLarge(.en).contains("\(mb)MB"))
    }

    // Backstop for the whole migration: catch a copy-paste bug where a Korean string
    // was accidentally left in the .en branch (or vice versa). Covers the parameterless
    // string functions (excludes endonyms, which are intentionally identical in both).
    func testEveryStringDiffersBetweenLanguages() {
        let fns: [(Language) -> String] = [
            L10n.colorYellow, L10n.colorPink, L10n.colorBlue, L10n.colorGreen, L10n.colorPurple,
            L10n.defaultColorLabel, L10n.recentErrorsHeader, L10n.newFromClipboard, L10n.openMarkdownFile,
            L10n.noStickers, L10n.emptyPreview, L10n.hideAll, L10n.showAll, L10n.bringAllToFront,
            L10n.exportSticker, L10n.closeAll, L10n.aboutPostMD, L10n.quit,
            L10n.languageMenu, L10n.languageSystem,
            L10n.closeSticker, L10n.unpin, L10n.pin, L10n.color, L10n.opacity, L10n.colorAndOpacity, L10n.edit,
            L10n.fileLink, L10n.showInFinder, L10n.openInEditor, L10n.detach, L10n.saved,
            L10n.saveToSourceFile, L10n.bothChanged, L10n.takeFile, L10n.keepMyEdits,
            L10n.linkedFileTooLarge, L10n.cancel, L10n.save,
            L10n.undo, L10n.redo, L10n.cut, L10n.copy, L10n.paste, L10n.selectAll,
            L10n.contentTooLargeMB, L10n.couldNotSaveEdits, L10n.contentTooLarge,
            L10n.unnamedFile, L10n.linkedFileNotFound, L10n.keepDetach, L10n.close,
            L10n.clipboardEmpty, L10n.onlyMarkdown, L10n.fileTooLargeMB, L10n.sourceNotFound,
            L10n.sourceChangedExternally, L10n.overwrite,
            L10n.urlUnknownHost, L10n.urlMissingContent, L10n.urlInvalidEncoding,
            L10n.cannotOpenLinkedFile,
        ]
        for fn in fns {
            XCTAssertNotEqual(fn(.en), fn(.ko), "en and ko must differ: got \"\(fn(.en))\"")
        }
    }
}
