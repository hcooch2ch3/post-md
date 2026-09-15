import XCTest
@testable import PostMDCore

final class StickyStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    override func setUp() {
        defaults = UserDefaults(suiteName: "test.post-md")!
        defaults.removePersistentDomain(forName: "test.post-md")
    }

    func makeStore() -> StickyStore { StickyStore(defaults: defaults, screenFrame: screen) }

    func testAddPlacesTopRightThenCascades() {
        let store = makeStore()
        let a = try! store.add(content: "a").get()
        let b = try! store.add(content: "b").get()
        XCTAssertGreaterThan(a.frame.maxX, screen.width * 0.6)   // top-right
        XCTAssertGreaterThan(a.frame.maxY, screen.height * 0.6)
        XCTAssertEqual(b.frame.origin.x, a.frame.origin.x - 24)  // 24px cascade
        XCTAssertEqual(b.frame.origin.y, a.frame.origin.y - 24)
    }

    func testCascadeWrapsWhenOffscreen() {
        let store = makeStore()
        var frames: [CGRect] = []
        for i in 0..<StickyStore.maxStickies {
            frames.append(try! store.add(content: "n\(i)").get().frame)
        }
        for f in frames { XCTAssertTrue(screen.contains(f), "\(f) offscreen") }
    }

    func testSoftCap() {
        let store = makeStore()
        for i in 0..<StickyStore.maxStickies { _ = store.add(content: "n\(i)") }
        if case .failure(let e) = store.add(content: "over") {
            XCTAssertEqual(e, .capReached)
        } else { XCTFail("cap not enforced") }
    }

    func testPersistRoundTrip() {
        let store = makeStore()
        let note = try! store.add(content: "안녕🎉").get()
        store.commitFrame(id: note.id, frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        store.commitOpacity(id: note.id, opacity: 0.7)

        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes.count, 1)
        XCTAssertEqual(store2.notes[0].content, "안녕🎉")
        XCTAssertEqual(store2.notes[0].frame, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(store2.notes[0].opacity, 0.7)
    }

    func testRestoreIsolatesCorruptItems() {
        let good = """
        {"schemaVersion":1,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"ok",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0},
          {"id":"not-a-uuid","content":123}
        ]}
        """
        defaults.set(good.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        store.restore()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes[0].content, "ok")
    }

    func testUnsupportedSchemaVersionNotLoaded() {
        // schemaVersion 2 → skip restore (prevents downgrade and data loss)
        let future = """
        {"schemaVersion":2,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"future",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0}
        ]}
        """
        defaults.set(future.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        store.restore()
        XCTAssertEqual(store.notes.count, 0)
    }

    func testRestoreIsolatesCorruptItems_badThenGood() {
        // a corrupt item first still lets a later valid item survive (order-independent)
        let json = """
        {"schemaVersion":1,"notes":[
          {"id":"not-a-uuid","content":123},
          {"id":"22222222-2222-2222-2222-222222222222","content":"good",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0}
        ]}
        """
        defaults.set(json.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        store.restore()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes[0].content, "good")
    }

    func testAddRejectsOversizeContent() {
        // Content byte cap: exactly at the limit is allowed, one byte over is .contentTooLarge (re-review)
        let store = makeStore()
        let atCap = String(repeating: "a", count: StickyStore.maxContentBytes)
        if case .failure = store.add(content: atCap) { XCTFail("exactly at the limit must be allowed") }
        let overCap = String(repeating: "a", count: StickyStore.maxContentBytes + 1)
        if case .failure(let e) = store.add(content: overCap) {
            XCTAssertEqual(e, .contentTooLarge)
        } else { XCTFail("over the limit must be .contentTooLarge") }
    }

    func testAddContentCapCountsBytesNotChars() {
        // Multibyte is judged by UTF-8 bytes, not character count (Hangul is 3 bytes)
        let store = StickyStore(defaults: defaults, screenFrame: screen)
        // Fill just under maxContentBytes with Hangul to confirm byte-based judgement (char count < byte count)
        let charCount = StickyStore.maxContentBytes / 3      // charCount Hangul chars = 3*charCount bytes, within the limit
        let ok = String(repeating: "가", count: charCount)
        XCTAssertLessThanOrEqual(ok.utf8.count, StickyStore.maxContentBytes)
        if case .failure = store.add(content: ok) { XCTFail("Korean within the byte limit is allowed") }
        let over = String(repeating: "가", count: charCount + 1) // 3 more bytes → over the limit
        if case .failure(let e) = store.add(content: over) {
            XCTAssertEqual(e, .contentTooLarge)
        } else { XCTFail("Korean over the byte limit is .contentTooLarge") }
    }

    func testRestoreDropsOversizeContent() {
        // Notes >1MB saved under the old (larger) cap must be dropped on restore (prevents render freeze, re-review MAJOR)
        let big = String(repeating: "a", count: StickyStore.maxContentBytes + 100)
        let json = """
        {"schemaVersion":1,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"\(big)",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0},
          {"id":"22222222-2222-2222-2222-222222222222","content":"ok",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0}
        ]}
        """
        defaults.set(json.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        store.restore()
        XCTAssertEqual(store.notes.count, 1)          // big note dropped, only the 1 valid one
        XCTAssertEqual(store.notes[0].content, "ok")
    }

    func testRestoreClampsToCap() {
        // An over-cap saved state (35 notes) is normalized to maxStickies on restore
        var notesJSON: [String] = []
        for i in 0..<35 {
            let uuid = String(format: "%08d-0000-0000-0000-000000000000", i)
            notesJSON.append("{\"id\":\"\(uuid)\",\"content\":\"n\(i)\",\"frame\":[[0,0],[100,100]],\"opacity\":1,\"createdAt\":0}")
        }
        let json = "{\"schemaVersion\":1,\"notes\":[\(notesJSON.joined(separator: ","))]}"
        defaults.set(json.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        store.restore()
        XCTAssertEqual(store.notes.count, StickyStore.maxStickies)
    }

    func testRestoreReportsDropCounts() {
        // report drop counts so the caller can notify the user about restore drops.
        // Setup: 2 oversize + 34 valid = 36 → withinSize 34; 4 over the cap (30) are clipped → restored 30.
        let big = String(repeating: "a", count: StickyStore.maxContentBytes + 100)
        var notesJSON: [String] = []
        for i in 0..<2 {
            let uuid = String(format: "%08d-1111-1111-1111-111111111111", i)
            notesJSON.append("{\"id\":\"\(uuid)\",\"content\":\"\(big)\",\"frame\":[[0,0],[100,100]],\"opacity\":1,\"createdAt\":0}")
        }
        for i in 0..<34 {
            let uuid = String(format: "%08d-2222-2222-2222-222222222222", i)
            notesJSON.append("{\"id\":\"\(uuid)\",\"content\":\"n\(i)\",\"frame\":[[0,0],[100,100]],\"opacity\":1,\"createdAt\":0}")
        }
        let json = "{\"schemaVersion\":1,\"notes\":[\(notesJSON.joined(separator: ","))]}"
        defaults.set(json.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        let outcome = store.restore()
        XCTAssertEqual(outcome.droppedOversize, 2)
        XCTAssertEqual(outcome.droppedOverCap, 4)   // withinSize 34 - clamp 30
        XCTAssertEqual(outcome.restored, StickyStore.maxStickies)
        XCTAssertTrue(outcome.hasDrops)
        XCTAssertEqual(store.notes.count, StickyStore.maxStickies)
    }

    func testRestoreCleanStateReportsNoDrops() {
        // A clean restore (no drops) has hasDrops == false → no user notification
        let store = makeStore()
        _ = try! store.add(content: "a").get()
        let store2 = makeStore()
        let outcome = store2.restore()
        XCTAssertFalse(outcome.hasDrops)
        XCTAssertEqual(outcome.restored, 1)
        XCTAssertEqual(outcome.droppedOversize, 0)
        XCTAssertEqual(outcome.droppedOverCap, 0)
    }

    func testRestoreCompactsDroppedBlob() {
        // The normalized result after dropping is persisted, so a re-restore does not repeat the drop (A-Minor: restore compaction).
        let big = String(repeating: "a", count: StickyStore.maxContentBytes + 100)
        let json = """
        {"schemaVersion":1,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"\(big)",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0},
          {"id":"22222222-2222-2222-2222-222222222222","content":"ok",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0}
        ]}
        """
        defaults.set(json.data(using: .utf8), forKey: "stickyStore.v1")
        let first = makeStore().restore()
        XCTAssertTrue(first.hasDrops)                 // first restore: big note dropped
        let second = makeStore().restore()
        XCTAssertFalse(second.hasDrops)               // re-restore: already compacted, no drops
        XCTAssertEqual(second.restored, 1)
    }

    func testRemovePersists() {
        let store = makeStore()
        let note = try! store.add(content: "a").get()
        store.remove(id: note.id)
        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes.count, 0)
    }

    func testMigrationV1NoteWithoutPinnedSurvivesFullFidelity() {
        // A v1 save without the pinned field, decoded into the new struct: all fields round-trip and pinned == nil survives
        let v1 = """
        {"schemaVersion":1,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"레거시",
           "frame":[[10,20],[300,200]],"opacity":0.8,"createdAt":0}
        ]}
        """
        defaults.set(v1.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        store.restore()
        XCTAssertEqual(store.notes.count, 1)
        let n = store.notes[0]
        XCTAssertEqual(n.content, "레거시")
        XCTAssertEqual(n.frame, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(n.opacity, 0.8)
        XCTAssertNil(n.pinned)
    }

    // MARK: Live Sync, syncedHash field

    func testSyncedHashDefaultsNilAndMigrates() {
        // New notes default to nil, and an existing save (field absent) decodes to nil
        let store = makeStore()
        let n = try! store.add(content: "x").get()
        XCTAssertNil(n.syncedHash)
        let v1 = """
        {"schemaVersion":1,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"레거시",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0}
        ]}
        """
        defaults.set(v1.data(using: .utf8), forKey: "stickyStore.v1")
        let s2 = makeStore(); s2.restore()
        XCTAssertNil(s2.notes[0].syncedHash)
    }

    // MARK: Live Sync, restore seeding

    func testRestoreSeedsSyncedHashForLinkedNotes() {
        // Restoring a Phase 1 save (linked note, no syncedHash) seeds it from the content hash
        let json = """
        {"schemaVersion":1,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"파일내용",
           "frame":[[0,0],[100,100]],"opacity":1,"createdAt":0,"sourcePath":"/tmp/a.md"}
        ]}
        """
        defaults.set(json.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore(); store.restore()
        XCTAssertEqual(store.notes[0].syncedHash, ContentHash.sha256Hex("파일내용"))
        // review consensus: seeding is persisted via save(), so it survives a re-restore and does not re-seed
        let s2 = makeStore(); s2.restore()
        XCTAssertEqual(s2.notes[0].syncedHash, ContentHash.sha256Hex("파일내용"))
    }
    func testRestoreDoesNotSeedIndependentNotes() {
        // not linked (sourcePath nil) → no seeding
        let store = makeStore()
        _ = try! store.add(content: "독립").get()
        let s2 = makeStore(); s2.restore()
        XCTAssertNil(s2.notes[0].syncedHash)
    }

    // MARK: Live Sync, store methods

    func testLinkToFileSetsLinkMetaAndHash() {
        let store = makeStore()
        let n = try! store.add(content: "hello").get()   // standalone (no source)
        XCTAssertNil(store.notes[0].sourcePath)
        store.linkToFile(id: n.id, sourcePath: "/tmp/new.md", sourceBookmark: Data([9]), syncedHash: "cafe")
        let m = store.notes[0]
        XCTAssertEqual(m.sourcePath, "/tmp/new.md")
        XCTAssertEqual(m.sourceBookmark, Data([9]))
        XCTAssertEqual(m.syncedHash, "cafe")
        XCTAssertEqual(m.content, "hello")   // content unchanged
    }
    func testLinkToFileNoOpForUnknownID() {
        let store = makeStore()
        _ = try! store.add(content: "x").get()
        store.linkToFile(id: UUID(), sourcePath: "/tmp/z.md", sourceBookmark: nil, syncedHash: "z")
        XCTAssertNil(store.notes[0].sourcePath)   // untouched
    }
    func testDetachFromFileClearsAllLinkMeta() {
        let store = makeStore()
        let n = try! store.add(content: "c", sourcePath: "/tmp/a.md", sourceBookmark: Data([1])).get()
        store.setSyncedHash(id: n.id, hash: "deadbeef")
        store.detachFromFile(id: n.id)
        let m = store.notes[0]
        XCTAssertNil(m.sourcePath); XCTAssertNil(m.sourceBookmark)
        XCTAssertNil(m.sourceModifiedDate); XCTAssertNil(m.syncedHash)
        XCTAssertEqual(m.content, "c")   // content preserved
    }
    func testApplyFileSyncUpdatesContentAndHash() {
        let store = makeStore()
        let n = try! store.add(content: "old", sourcePath: "/tmp/a.md", sourceBookmark: nil).get()
        let r = store.applyFileSync(id: n.id, content: "new", hash: "abc")
        if case .failure = r { XCTFail("normal apply failed") }
        XCTAssertEqual(store.notes[0].content, "new")
        XCTAssertEqual(store.notes[0].syncedHash, "abc")
    }
    func testApplyFileSyncRejectsOversize() {
        let store = makeStore()
        let n = try! store.add(content: "ok", sourcePath: "/tmp/a.md", sourceBookmark: nil).get()
        store.setSyncedHash(id: n.id, hash: "seed")
        let big = String(repeating: "a", count: StickyStore.maxContentBytes + 1)
        if case .failure(let e) = store.applyFileSync(id: n.id, content: big, hash: "x") {
            XCTAssertEqual(e, .contentTooLarge)
        } else { XCTFail("expected .contentTooLarge") }
        XCTAssertEqual(store.notes[0].content, "ok")       // not applied
        XCTAssertEqual(store.notes[0].syncedHash, "seed")  // hash unchanged
    }
    func testSetSourcePathUpdatesPathAndBookmark() {
        let store = makeStore()
        let n = try! store.add(content: "c", sourcePath: "/tmp/old.md", sourceBookmark: nil).get()
        store.setSourcePath(id: n.id, path: "/tmp/new.md", bookmark: Data([9]))
        XCTAssertEqual(store.notes[0].sourcePath, "/tmp/new.md")
        XCTAssertEqual(store.notes[0].sourceBookmark, Data([9]))
    }
    func testApplyFileSyncAtExactCapSucceeds() {
        // review consensus: `<=` boundary, exactly at the limit must apply (guards against an accidental `<` regression)
        let store = makeStore()
        let n = try! store.add(content: "seed", sourcePath: "/tmp/a.md", sourceBookmark: nil).get()
        let atCap = String(repeating: "a", count: StickyStore.maxContentBytes)
        if case .failure = store.applyFileSync(id: n.id, content: atCap, hash: "h") {
            XCTFail("exactly at the limit must apply")
        }
        XCTAssertEqual(store.notes[0].content.utf8.count, StickyStore.maxContentBytes)
        XCTAssertEqual(store.notes[0].syncedHash, "h")
    }
    func testDetachFromFilePersistsRoundTrip() {
        // review consensus: detach goes through save(), so after a re-restore the link is cleared and content preserved
        let store = makeStore()
        let n = try! store.add(content: "keep", sourcePath: "/tmp/a.md", sourceBookmark: Data([1])).get()
        store.setSyncedHash(id: n.id, hash: "h")
        store.detachFromFile(id: n.id)
        let store2 = makeStore(); store2.restore()
        XCTAssertNil(store2.notes[0].sourcePath)
        XCTAssertNil(store2.notes[0].syncedHash)
        XCTAssertEqual(store2.notes[0].content, "keep")
    }

    // MARK: inline editing (updateContent)

    func testUpdateContentChangesAndPersists() {
        let store = makeStore()
        let note = try! store.add(content: "원본").get()
        if case .failure = store.updateContent(id: note.id, content: "수정됨") { XCTFail("normal update failed") }
        XCTAssertEqual(store.notes[0].content, "수정됨")
        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes[0].content, "수정됨")
    }

    func testUpdateContentRejectsOversize() {
        let store = makeStore()
        let note = try! store.add(content: "작음").get()
        let over = String(repeating: "a", count: StickyStore.maxContentBytes + 1)
        if case .failure(let e) = store.updateContent(id: note.id, content: over) {
            XCTAssertEqual(e, .contentTooLarge)
        } else { XCTFail("over the limit must be .contentTooLarge") }
        XCTAssertEqual(store.notes[0].content, "작음")   // original unchanged
    }

    func testUpdateContentUnknownIdReturnsNotFound() {
        // Existing mutators are no-ops, but updateContent must surface a failed edit save, so it errors
        let store = makeStore()
        if case .failure(let e) = store.updateContent(id: UUID(), content: "x") {
            XCTAssertEqual(e, .noteNotFound)
        } else { XCTFail("a nonexistent id is .noteNotFound") }
    }

    // MARK: file-link fields (convenience feature Phase 1: import + link save)

    func testAddWithSourcePathStoresAndRoundTrips() {
        // When created by opening a file, sourcePath/sourceBookmark are stored and survive the round trip
        let store = makeStore()
        let bookmark = Data([0x01, 0x02, 0x03])
        let note = try! store.add(content: "# 파일 내용",
                                  sourcePath: "/tmp/example.md",
                                  sourceBookmark: bookmark).get()
        XCTAssertEqual(note.sourcePath, "/tmp/example.md")
        XCTAssertEqual(note.sourceBookmark, bookmark)

        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes.count, 1)
        XCTAssertEqual(store2.notes[0].sourcePath, "/tmp/example.md")
        XCTAssertEqual(store2.notes[0].sourceBookmark, bookmark)
    }

    func testAddStoresSourceModifiedDate() {
        // On file open, store the source mtime as the baseline for write-back conflict detection (survives round trip)
        let store = makeStore()
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        let note = try! store.add(content: "x", sourcePath: "/tmp/a.md",
                                  sourceBookmark: nil, sourceModifiedDate: mtime).get()
        XCTAssertEqual(note.sourceModifiedDate, mtime)
        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes[0].sourceModifiedDate, mtime)
    }

    func testSetSourceModifiedDatePersists() {
        // After a successful save, update mtime to refresh the conflict baseline for the next save
        let store = makeStore()
        let note = try! store.add(content: "x", sourcePath: "/tmp/a.md", sourceBookmark: nil).get()
        XCTAssertNil(note.sourceModifiedDate)
        let newMtime = Date(timeIntervalSince1970: 1_700_000_500)
        store.setSourceModifiedDate(id: note.id, date: newMtime)
        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes[0].sourceModifiedDate, newMtime)
    }

    func testAddWithoutSourceHasNilFields() {
        // An independent sticker made via the existing path (clipboard/URL) has nil source fields
        let store = makeStore()
        let note = try! store.add(content: "독립").get()
        XCTAssertNil(note.sourcePath)
        XCTAssertNil(note.sourceBookmark)
    }

    func testMigrationV1NoteWithoutSourceFieldsSurvives() {
        // A save without source fields, decoded into the new struct, fills them with nil and survives (schemaVersion 1 kept)
        let v1 = """
        {"schemaVersion":1,"notes":[
          {"id":"11111111-1111-1111-1111-111111111111","content":"레거시",
           "frame":[[10,20],[300,200]],"opacity":0.8,"createdAt":0}
        ]}
        """
        defaults.set(v1.data(using: .utf8), forKey: "stickyStore.v1")
        let store = makeStore()
        store.restore()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertNil(store.notes[0].sourcePath)
        XCTAssertNil(store.notes[0].sourceBookmark)
    }

    func testAddWithSourceStillEnforcesOversize() {
        // The link-save path also enforces the content byte cap
        let store = makeStore()
        let over = String(repeating: "a", count: StickyStore.maxContentBytes + 1)
        if case .failure(let e) = store.add(content: over, sourcePath: "/tmp/big.md", sourceBookmark: nil) {
            XCTAssertEqual(e, .contentTooLarge)
        } else { XCTFail("over the limit must be .contentTooLarge") }
    }

    func testSetColorPersistsRoundTrip() {
        // Sticky-note color: store the palette key and survive the round trip. Default is nil.
        let store = makeStore()
        let note = try! store.add(content: "색").get()
        XCTAssertNil(store.notes[0].color)     // default = no color
        store.setColor(id: note.id, color: "yellow")
        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes.count, 1)
        XCTAssertEqual(store2.notes[0].color, "yellow")
    }

    func testSetColorNilClearsColor() {
        let store = makeStore()
        let note = try! store.add(content: "색").get()
        store.setColor(id: note.id, color: "pink")
        store.setColor(id: note.id, color: nil)   // back to default
        XCTAssertNil(store.notes[0].color)
    }

    func testSetPinnedPersistsRoundTrip() {
        let store = makeStore()
        let note = try! store.add(content: "핀").get()
        XCTAssertNil(store.notes[0].pinned)     // default is unpinned
        store.setPinned(id: note.id, pinned: true)
        let store2 = makeStore()
        store2.restore()
        XCTAssertEqual(store2.notes.count, 1)
        XCTAssertEqual(store2.notes[0].pinned, true)
    }

    // Regression (auto-write-back C1): a linked add must return a note that already carries the
    // seeded syncedHash. StickyNote is a value type, so openFile hands the RETURNED note to the VM;
    // if the baseline weren't seeded here, vm.syncedHash would be nil and `diverged`/⬆️/⌘Return
    // write-back would be dead for the session.
    func testLinkedAddSeedsSyncedHashOnReturnedNote() {
        let store = makeStore()
        guard case .success(let note) = store.add(content: "hello", sourcePath: "/tmp/x.md", sourceBookmark: nil) else {
            return XCTFail("linked add failed")
        }
        XCTAssertEqual(note.syncedHash, ContentHash.sha256Hex("hello"))
    }

    func testUnlinkedAddLeavesSyncedHashNil() {
        let store = makeStore()
        guard case .success(let note) = store.add(content: "hi") else { return XCTFail("add failed") }
        XCTAssertNil(note.syncedHash)
    }
}
