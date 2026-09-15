import XCTest
@testable import PostMDCore

final class FileWatcherTests: XCTestCase {
    func testDetectsInPlaceWriteAndReArmsAfterAtomicSave() {
        let dir = NSTemporaryDirectory() + "fwtest-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/n.md"
        try! "v0".write(toFile: path, atomically: false, encoding: .utf8)
        let w = FileWatcher()
        let exp = expectation(description: "change"); exp.expectedFulfillmentCount = 2
        exp.assertForOverFulfill = false   // watcher may fire >2 via .write/.extend/re-arm, so require only >=2
        var events = 0
        w.watch(noteID: UUID(), url: URL(fileURLWithPath: path)) { events += 1; exp.fulfill() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(" x".utf8)); try? h.close() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {   // atomic save
            let tmp = dir + "/.tmp"; try! "v1".write(toFile: tmp, atomically: false, encoding: .utf8)
            rename(tmp, path)
        }
        wait(for: [exp], timeout: 4)
        XCTAssertGreaterThanOrEqual(events, 2)
        w.unwatchAll()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // Regression: after a rename schedules a debounce re-arm, unwatching within that
    // 150ms window must cancel the scheduled re-arm so no further ping arrives (prevents zombie
    // watcher revival and spurious dialogs).
    func testUnwatchDuringRearmWindowCancelsPendingRearm() {
        let dir = NSTemporaryDirectory() + "fwtest-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/n.md"
        try! "v0".write(toFile: path, atomically: false, encoding: .utf8)
        let w = FileWatcher()
        let id = UUID()
        var unwatched = false
        var pingsAfterUnwatch = 0
        w.watch(noteID: id, url: URL(fileURLWithPath: path)) { if unwatched { pingsAfterUnwatch += 1 } }
        // rename event fires → schedules re-arm at +0.15s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let tmp = dir + "/.tmp"; try! "v1".write(toFile: tmp, atomically: false, encoding: .utf8)
            rename(tmp, path)
        }
        // unwatch inside the re-arm window (150ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            unwatched = true
            w.unwatch(noteID: id)
        }
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(pingsAfterUnwatch, 0, "a re-arm ping must not fire after unwatch")
        w.unwatchAll()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // Regression: unwatchAll must also cancel a mid-rearm note
    // (absent from watches but present in rearmWork). Calling unwatchAll inside the re-arm window
    // after a rename should leave no further ping.
    func testUnwatchAllDuringRearmWindowCancelsPendingRearm() {
        let dir = NSTemporaryDirectory() + "fwtest-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/n.md"
        try! "v0".write(toFile: path, atomically: false, encoding: .utf8)
        let w = FileWatcher()
        var unwatched = false
        var pingsAfterUnwatch = 0
        w.watch(noteID: UUID(), url: URL(fileURLWithPath: path)) { if unwatched { pingsAfterUnwatch += 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let tmp = dir + "/.tmp"; try! "v1".write(toFile: tmp, atomically: false, encoding: .utf8)
            rename(tmp, path)   // rename → schedules re-arm at +0.15s; at this moment it is removed from watches
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {   // inside the re-arm window
            unwatched = true
            w.unwatchAll()
        }
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(pingsAfterUnwatch, 0, "a mid-rearm ping must not fire after unwatchAll")
        try? FileManager.default.removeItem(atPath: dir)
    }
}
