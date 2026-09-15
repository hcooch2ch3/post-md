import Foundation

public enum Language { case en, ko }

// 3-state override (Decision 1). `.system` means "follow OS detection".
public enum LanguageOverride: String { case system, en, ko }

public enum L10n {
    private static let overrideKey = "StickyCastLanguageOverride"

    // Injectable defaults store so tests never touch the real `UserDefaults.standard`
    // domain (would persist a stray key on the developer's machine). Production uses `.standard`.
    static var store: UserDefaults = .standard

    public static var override: LanguageOverride {
        get { LanguageOverride(rawValue: store.string(forKey: overrideKey) ?? "") ?? .system }
        set { store.set(newValue.rawValue, forKey: overrideKey) }
    }

    // Pure, injectable detection seam — tests call this directly (no process-locale mutation).
    // Match the PRIMARY subtag exactly so "kok"/"kos" do NOT map to Korean.
    public static func language(for preferred: [String]) -> Language {
        let primary = preferred.first?.split(separator: "-").first.map(String.init)
        return primary == "ko" ? .ko : .en
    }

    // Effective language: override wins, else OS detection.
    public static var current: Language {
        switch override {
        case .en: return .en
        case .ko: return .ko
        case .system: return language(for: Locale.preferredLanguages)
        }
    }

    // Size-in-MB, single source of truth (never hardcode "1MB").
    private static var maxMB: Int { StickyStore.maxContentBytes / (1024 * 1024) }

    // MARK: Palette color labels
    public static func colorYellow(_ l: Language = current) -> String { switch l { case .en: "Yellow"; case .ko: "노랑" } }
    public static func colorPink(_ l: Language = current)   -> String { switch l { case .en: "Pink";   case .ko: "분홍" } }
    public static func colorBlue(_ l: Language = current)   -> String { switch l { case .en: "Blue";   case .ko: "파랑" } }
    public static func colorGreen(_ l: Language = current)  -> String { switch l { case .en: "Green";  case .ko: "초록" } }
    public static func colorPurple(_ l: Language = current) -> String { switch l { case .en: "Purple"; case .ko: "보라" } }
    public static func defaultColorLabel(_ l: Language = current) -> String { switch l { case .en: "Default"; case .ko: "기본" } }

    // MARK: Menu bar
    public static func recentErrorsHeader(_ l: Language = current) -> String { switch l { case .en: "⚠︎ Recent errors"; case .ko: "⚠︎ 최근 오류" } }
    public static func newFromClipboard(_ l: Language = current) -> String { switch l { case .en: "New sticker from clipboard"; case .ko: "클립보드에서 스티커" } }
    public static func openMarkdownFile(_ l: Language = current) -> String { switch l { case .en: "Open Markdown file…"; case .ko: "마크다운 파일 열기…" } }
    public static func newBlankSticky(_ l: Language = current) -> String { switch l { case .en: "New blank sticker"; case .ko: "빈 스티커 새로 만들기" } }
    public static func noStickers(_ l: Language = current) -> String { switch l { case .en: "No stickers"; case .ko: "스티커 없음" } }
    public static func emptyPreview(_ l: Language = current) -> String { switch l { case .en: "(empty)"; case .ko: "(빈 내용)" } }
    public static func hideAll(_ l: Language = current) -> String { switch l { case .en: "Hide all"; case .ko: "모두 숨기기" } }
    public static func showAll(_ l: Language = current) -> String { switch l { case .en: "Show all"; case .ko: "모두 보이기" } }
    public static func bringAllToFront(_ l: Language = current) -> String { switch l { case .en: "Bring all to front"; case .ko: "모두 앞으로" } }
    public static func exportSticker(_ l: Language = current) -> String { switch l { case .en: "Export sticker"; case .ko: "스티커 내보내기" } }
    public static func closeAll(_ l: Language = current) -> String { switch l { case .en: "Close all"; case .ko: "모두 닫기" } }
    public static func aboutStickyCast(_ l: Language = current) -> String { switch l { case .en: "About StickyCast"; case .ko: "StickyCast에 관하여" } }
    public static func aboutCredits(_ l: Language = current) -> String {
        switch l {
        case .en: return "Markdown rendering: swift-markdown-ui (MIT)\nMarkEdit companion tool"
        case .ko: return "마크다운 렌더링: swift-markdown-ui (MIT)\nMarkEdit 동반 도구"
        }
    }
    public static func quit(_ l: Language = current) -> String { switch l { case .en: "Quit"; case .ko: "종료" } }

    // MARK: Language submenu (Task 3)
    public static func languageMenu(_ l: Language = current) -> String { switch l { case .en: "Language"; case .ko: "언어" } }
    public static func languageSystem(_ l: Language = current) -> String { switch l { case .en: "System"; case .ko: "시스템" } }
    public static func languageEnglish(_ l: Language = current) -> String { "English" }
    public static func languageKorean(_ l: Language = current) -> String { "한국어" }  // endonym: constant in both

    // MARK: StickyContentView
    public static func closeSticker(_ l: Language = current) -> String { switch l { case .en: "Close sticker"; case .ko: "스티커 닫기" } }
    public static func unpin(_ l: Language = current) -> String { switch l { case .en: "Unpin"; case .ko: "핀 해제" } }
    public static func pin(_ l: Language = current) -> String { switch l { case .en: "Pin"; case .ko: "핀 고정" } }
    public static func color(_ l: Language = current) -> String { switch l { case .en: "Color"; case .ko: "색상" } }
    public static func opacity(_ l: Language = current) -> String { switch l { case .en: "Opacity"; case .ko: "투명도" } }
    public static func edit(_ l: Language = current) -> String { switch l { case .en: "Edit"; case .ko: "편집" } }
    public static func fileLink(_ l: Language = current) -> String { switch l { case .en: "File link"; case .ko: "파일 연결" } }
    public static func showInFinder(_ l: Language = current) -> String { switch l { case .en: "Show in Finder"; case .ko: "Finder에서 보기" } }
    public static func openInEditor(_ l: Language = current) -> String { switch l { case .en: "Open in editor"; case .ko: "원본 편집기로 열기" } }
    public static func detach(_ l: Language = current) -> String { switch l { case .en: "Detach"; case .ko: "연결 해제" } }
    public static func saved(_ l: Language = current) -> String { switch l { case .en: "Saved"; case .ko: "저장됨" } }
    public static func saveToSourceFile(_ l: Language = current) -> String { switch l { case .en: "Save to source file"; case .ko: "원본 파일에 저장" } }
    public static func saveToNewFile(_ l: Language = current) -> String { switch l { case .en: "Save to file…"; case .ko: "파일로 저장…" } }
    public static func bothChanged(_ l: Language = current) -> String { switch l { case .en: "Both file and sticker changed"; case .ko: "파일과 스티커가 모두 변경됨" } }
    public static func takeFile(_ l: Language = current) -> String { switch l { case .en: "Take file"; case .ko: "파일 가져오기" } }
    public static func keepMyEdits(_ l: Language = current) -> String { switch l { case .en: "Keep my edits"; case .ko: "내 편집 유지" } }
    public static func linkedFileTooLarge(_ l: Language = current) -> String {
        switch l {
        case .en: return "Linked file too large (max ~\(maxMB)MB) — not applied"
        case .ko: return "연결 파일이 너무 큼 (최대 약 \(maxMB)MB) — 반영 안 됨"
        }
    }
    public static func cancel(_ l: Language = current) -> String { switch l { case .en: "Cancel"; case .ko: "취소" } }
    public static func save(_ l: Language = current) -> String { switch l { case .en: "Save"; case .ko: "저장" } }

    // MARK: Edit menu (carries the standard clipboard key equivalents)
    public static func undo(_ l: Language = current) -> String { switch l { case .en: "Undo"; case .ko: "실행 취소" } }
    public static func redo(_ l: Language = current) -> String { switch l { case .en: "Redo"; case .ko: "다시 실행" } }
    public static func cut(_ l: Language = current) -> String { switch l { case .en: "Cut"; case .ko: "오려두기" } }
    public static func copy(_ l: Language = current) -> String { switch l { case .en: "Copy"; case .ko: "복사하기" } }
    public static func paste(_ l: Language = current) -> String { switch l { case .en: "Paste"; case .ko: "붙여넣기" } }
    public static func selectAll(_ l: Language = current) -> String { switch l { case .en: "Select All"; case .ko: "전체 선택" } }

    // MARK: StickyPanelController + AppDelegate errors
    public static func contentTooLargeMB(_ l: Language = current) -> String {
        switch l {
        case .en: return "Sticker content is too large (max ~\(maxMB)MB)."
        case .ko: return "스티커 내용이 너무 큽니다 (최대 약 \(maxMB)MB)."
        }
    }
    public static func couldNotSaveEdits(_ l: Language = current) -> String { switch l { case .en: "Couldn't save your edits."; case .ko: "편집 내용을 저장하지 못했습니다." } }
    public static func contentTooLarge(_ l: Language = current) -> String { switch l { case .en: "Sticker content is too large."; case .ko: "스티커 내용이 너무 큽니다." } }
    public static func maxStickiesReached(_ n: Int, _ l: Language = current) -> String {
        switch l {
        case .en:
            let noun = n == 1 ? "1 sticker" : "\(n) stickers"
            return "Sticker limit reached (max \(noun)). Close an existing sticker first."
        case .ko:
            return "스티커가 최대 \(n)장입니다. 기존 스티커를 닫아 주세요."
        }
    }
    public static func restoreOversize(_ n: Int, _ l: Language = current) -> String {
        switch l { case .en: "\(n) over the size limit"; case .ko: "크기 초과 \(n)개" }
    }
    public static func restoreOverCap(_ n: Int, _ l: Language = current) -> String {
        switch l { case .en: "\(n) over the sticker limit"; case .ko: "최대 장수 초과 \(n)개" }
    }
    public static func restoreFailed(_ parts: String, _ l: Language = current) -> String {
        switch l {
        case .en: return "Couldn't restore previous stickers (\(parts))."
        case .ko: return "이전 스티커 \(parts)를 복원하지 못했습니다."
        }
    }
    public static func unnamedFile(_ l: Language = current) -> String { switch l { case .en: "file"; case .ko: "파일" } }
    public static func linkedFileNotFound(_ l: Language = current) -> String { switch l { case .en: "Linked file not found"; case .ko: "연결된 파일을 찾을 수 없습니다" } }
    public static func linkedFileMissingBody(_ name: String, _ l: Language = current) -> String {
        switch l {
        case .en: return "'\(name)' was deleted or moved. What should happen to the sticker? (Its current content is kept.)"
        case .ko: return "'\(name)'이(가) 삭제/이동됐습니다. 스티커를 어떻게 할까요? (현재 내용은 보존됩니다)"
        }
    }
    public static func keepDetach(_ l: Language = current) -> String { switch l { case .en: "Keep (detach)"; case .ko: "유지 (독립 전환)" } }
    public static func close(_ l: Language = current) -> String { switch l { case .en: "Close"; case .ko: "닫기" } }
    public static func clipboardEmpty(_ l: Language = current) -> String { switch l { case .en: "No text on the clipboard to paste."; case .ko: "클립보드에 붙여넣을 텍스트가 없습니다." } }
    public static func onlyMarkdown(_ l: Language = current) -> String { switch l { case .en: "Only Markdown (.md/.markdown) files can be opened."; case .ko: "마크다운(.md/.markdown) 파일만 열 수 있습니다." } }
    public static func capReachedSomeFiles(_ n: Int, _ l: Language = current) -> String {
        switch l {
        case .en: return "Sticker limit (\(n)) reached; some files couldn't be opened."
        case .ko: return "스티커가 최대 \(n)장이라 일부 파일을 열지 못했습니다."
        }
    }
    public static func filesTooLarge(_ list: String, _ l: Language = current) -> String {
        switch l { case .en: "Files too large: \(list)"; case .ko: "파일이 너무 큽니다: \(list)" }
    }
    public static func unreadableFiles(_ list: String, _ l: Language = current) -> String {
        switch l { case .en: "Unreadable files: \(list)"; case .ko: "읽을 수 없는 파일: \(list)" }
    }
    public static func couldNotReadFile(_ name: String, _ l: Language = current) -> String {
        switch l {
        case .en: return "Couldn't read the file (\(name)). Make sure it's UTF-8 text."
        case .ko: return "파일을 읽을 수 없습니다 (\(name)). UTF-8 텍스트인지 확인해 주세요."
        }
    }
    public static func fileTooLargeMB(_ l: Language = current) -> String {
        switch l {
        case .en: return "File too large (max ~\(maxMB)MB)."
        case .ko: return "파일이 너무 큽니다 (최대 약 \(maxMB)MB)."
        }
    }
    public static func sourceNotFound(_ l: Language = current) -> String { switch l { case .en: "Source file not found. It may have been moved or deleted."; case .ko: "원본 파일을 찾을 수 없습니다. 이동/삭제됐을 수 있습니다." } }
    public static func sourceChangedExternally(_ l: Language = current) -> String { switch l { case .en: "Source file changed externally"; case .ko: "원본 파일이 외부에서 변경되었습니다" } }
    public static func overwriteBody(_ fileName: String, _ l: Language = current) -> String {
        switch l {
        case .en: return "Overwriting '\(fileName)' with the sticker's content discards the external changes. Continue?"
        case .ko: return "'\(fileName)'을(를) 스티커 내용으로 덮어쓰면 외부 변경분이 사라집니다. 계속할까요?"
        }
    }
    public static func overwrite(_ l: Language = current) -> String { switch l { case .en: "Overwrite"; case .ko: "덮어쓰기" } }
    public static func couldNotSaveToSource(_ name: String, _ l: Language = current) -> String {
        switch l {
        case .en: return "Couldn't save to the source file (\(name))."
        case .ko: return "원본 파일에 저장하지 못했습니다 (\(name))."
        }
    }
    public static func exportFailed(_ name: String, _ l: Language = current) -> String {
        switch l { case .en: "Export failed (\(name))."; case .ko: "내보내기에 실패했습니다 (\(name))." }
    }
    public static func saveToNewFileFailed(_ name: String, _ l: Language = current) -> String {
        switch l { case .en: "Couldn't save to file (\(name))."; case .ko: "파일에 저장하지 못했습니다 (\(name))." }
    }
    public static func handlerNotRegistered(_ l: Language = current) -> String {
        switch l {
        case .en: return "The sticky:// handler isn't registered, so popping stickers won't work — please reinstall the app."
        case .ko: return "sticky:// 핸들러가 등록되지 않았습니다. 스티커 발사가 동작하지 않습니다 — 앱을 다시 설치해 주세요."
        }
    }
    public static func handlerNotThisApp(_ name: String, _ l: Language = current) -> String {
        switch l {
        case .en: return "The sticky:// handler isn't this app (current: \(name)). Please reinstall the app."
        case .ko: return "sticky:// 핸들러가 이 앱이 아닙니다 (현재: \(name)). 앱을 다시 설치해 주세요."
        }
    }
    // URLError enum (verb-generic: sticky:// now has both new?content= and open?path=)
    public static func urlUnknownHost(_ l: Language = current) -> String { switch l { case .en: "Unsupported request."; case .ko: "지원하지 않는 요청입니다." } }
    public static func urlMissingContent(_ l: Language = current) -> String { switch l { case .en: "The request is missing its value."; case .ko: "요청에 값이 없습니다." } }
    public static func urlInvalidEncoding(_ l: Language = current) -> String { switch l { case .en: "Couldn't decode the request (encoding error)."; case .ko: "요청을 해석할 수 없습니다 (인코딩 오류)." } }
    // open?path= receiver-side guard failure
    public static func cannotOpenLinkedFile(_ l: Language = current) -> String { switch l { case .en: "Can't open that file — it may be missing, a folder, or not a text file."; case .ko: "그 파일을 열 수 없습니다 — 없거나, 폴더이거나, 텍스트 파일이 아닐 수 있습니다." } }
}
