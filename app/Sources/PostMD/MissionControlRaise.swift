import AppKit
import PostMDCore

/// Keeps a Mission Control raise from being undone.
///
/// Selecting a sticker in Mission Control activates this app and raises the panel, and then macOS hands
/// the front app back to whatever was active before — measured at 230–320ms after the activation, across
/// three different front apps. The returning app's front window rises over every `.normal` sticker, so
/// the raise the user asked for lasts a fraction of a second, and any sticker that was already sitting
/// above that app is dragged down with it. Nothing in this process requests the hand-back; why macOS
/// does it is unestablished (making the panel `canBecomeMain` does not stop it).
///
/// So rather than fight the activation, ride it out. On the trigger pair below, lift the selected sticker
/// — plus the ones already above other apps on the same screen, which have the same raise to lose — to
/// `.floating`. When the hand-back arrives, drop them back to their own levels and restore their order
/// with `orderFrontRegardless`, which puts a panel above the active app's windows without activating us.
/// It is the same primitive the status menu's "bring to front" already uses.
///
/// The end of the lift is driven by the hand-back notification rather than by a fixed delay, so a slower
/// machine holds the lift longer instead of dropping it early and losing the raise. `disarmDelay` is only
/// a cap for the case where no hand-back ever comes.
///
/// The lift is what keeps this seamless. Re-raising alone also survives the hand-back, but the returning
/// app's window ordering lands up to ~130ms after its activation notification, so the sticker visibly
/// drops out and pops back; measured, and rejected on that basis.
///
/// Guards keep this to the Mission Control path:
///  - a sticker must have become key around our activation. Mission Control keys the selected panel;
///    a click on a sticker cannot produce this pair, because `.nonactivatingPanel` means a click never
///    activates the app (StickyPanel.swift) — the invariant this whole trigger rests on
///  - the pair is consumed, so one activation arms exactly one lift
///  - the order is restored only when front goes back to the app we took it from. If the user
///    deliberately clicked into some other app instead, levels are restored and nothing is raised
///  - no modal window, so a sticker never jumps over an open save panel
final class MissionControlRaiseKeeper {
    /// Mission Control keys the selected panel within ~50ms of the activation, on either side of it, so
    /// the two halves of the trigger pair up within this window whichever one arrives first.
    private let pairingWindow: TimeInterval = 0.3
    /// The returning app's windows finish reordering after its activation notification; wait that out
    /// before handing the level back, or the drop lands into the middle of it.
    private let handBackGrace: TimeInterval = 0.15
    /// Nothing came back: drop the lift rather than leave a sticker floating.
    private let disarmDelay: TimeInterval = 1.0

    private weak var keyedPanel: StickyPanel?
    private var keyedAt = Date.distantPast
    private var activatedAt = Date.distantPast
    /// Most recent foreign activation. By the time we are lifting, this is the app Mission Control took
    /// front from — reading `frontmostApplication` there would just find us, since we were activated first.
    private var lastForeignApp: NSRunningApplication?
    /// Who we took front from for the lift in flight. nil when nothing is armed, so it cannot go stale
    /// and wave through an unrelated app switch later.
    private var displacedApp: NSRunningApplication?

    private struct Lifted { weak var panel: StickyPanel? }
    /// Front-to-back, selected panel first. Empty when no lift is in flight.
    private var lifted: [Lifted] = []
    private var pending: Timer?

    private var observers: [any NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }   // re-entry would double every handler

        // queue: nil keeps delivery synchronous on the posting thread (main, for all three), so the
        // timestamps below are when AppKit posted rather than when the main queue got around to us.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let self, let panel = note.object as? StickyPanel else { return }
            self.keyedPanel = panel
            self.keyedAt = Date()
            if self.keyedAt.timeIntervalSince(self.activatedAt) <= self.pairingWindow { self.lift(panel) }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            if app.processIdentifier == NSRunningApplication.current.processIdentifier {
                self.activatedAt = Date()
                if let panel = self.keyedPanel,
                   self.activatedAt.timeIntervalSince(self.keyedAt) <= self.pairingWindow { self.lift(panel) }
            } else {
                self.foreignAppActivated(app)
                self.lastForeignApp = app
            }
        })

        // Seed it, so a Mission Control trip taken before the first app switch of the session still knows
        // who to hand the front back to.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != NSRunningApplication.current.processIdentifier { lastForeignApp = front }
    }

    deinit {
        pending?.invalidate()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    // MARK: arming

    private func lift(_ selected: StickyPanel) {
        guard selected.isVisible, NSApp.modalWindow == nil else { return }
        // Consume the pair: one activation arms one lift, and a stale key event can't pair with a later
        // activation to drag some panel the user touched a moment ago along with the real selection.
        keyedAt = .distantPast
        activatedAt = .distantPast

        if lifted.isEmpty {
            displacedApp = lastForeignApp
            lifted = panelsAboveOtherApps(on: selected.screen).map(Lifted.init)
        }
        // A second selection inside the window joins the group in front rather than being dropped: two
        // Mission Control trips a few hundred ms apart is ordinary use, and the second sticker has the
        // same raise to lose as the first.
        lifted.removeAll { $0.panel == nil || $0.panel === selected }
        lifted.insert(Lifted(panel: selected), at: 0)

        // Back to front, so the selected panel is applied last and lands at the top of the lifted group.
        lifted.reversed().forEach { $0.panel?.level = .floating }
        schedule(after: disarmDelay)
    }

    private func foreignAppActivated(_ app: NSRunningApplication) {
        guard !lifted.isEmpty else { return }
        guard app.processIdentifier == displacedApp?.processIdentifier else {
            // The user went somewhere else on purpose. Give the levels back and leave the order alone.
            settle(restoreOrder: false)
            return
        }
        schedule(after: handBackGrace)   // the hand-back: let its window ordering land, then take the top back
    }

    private func schedule(after delay: TimeInterval) {
        pending?.invalidate()
        // .common mode: the wait spans Mission Control's animation, which runs the loop in tracking modes.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.settle(restoreOrder: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        pending = timer
    }

    // MARK: disarming

    private func settle(restoreOrder: Bool) {
        pending?.invalidate()
        pending = nil
        let group = lifted.compactMap(\.panel)
        lifted = []
        displacedApp = nil

        // Back to front again, and to each panel's own resting level rather than one captured at lift
        // time: a lift left in place would read as an accidental pin, and a pin toggled during the
        // lift has to win. Unconditional — the early return below must not be able to strand a lift.
        group.reversed().forEach { $0.level = $0.restingLevel }

        guard restoreOrder, NSApp.modalWindow == nil else { return }
        group.reversed().forEach { if $0.isVisible { $0.orderFrontRegardless() } }
    }

    // MARK: the current stack

    /// Our visible panels sitting above other apps' windows, scanned per screen and unioned, front-to-back
    /// within each screen and starting with `selectedScreen`.
    ///
    /// Every screen, not only the one being raised into: the hand-back re-activates the whole app, so its
    /// windows rise on every display it has one on. Scoping the group to the selected panel's screen was
    /// measured to drop a sticker that was sitting in front on the second display. Scanning per screen
    /// rather than once globally is still what keeps the group honest — one global walk ends at the first
    /// foreign window anywhere, which cuts off displays it never looked at.
    private func panelsAboveOtherApps(on selectedScreen: NSScreen?) -> [StickyPanel] {
        let windows = onScreenWindows()
        let ignored = systemUIPIDs(in: windows)
        let ourPID = NSRunningApplication.current.processIdentifier

        var screens = NSScreen.screens
        if let selectedScreen, let index = screens.firstIndex(of: selectedScreen) { screens.swapAt(0, index) }
        // No screens at all (nothing attached) means no filtering, rather than an empty group.
        let frames = screens.isEmpty ? [CGRect.infinite] : screens.map(displayFrame(of:))

        var numbers: [Int] = []
        for frame in frames {
            let found = WindowStackScan.windowNumbersAboveOtherApps(
                in: windows, ourPID: ourPID, screen: frame, ignoredPIDs: ignored
            )
            numbers.append(contentsOf: found.filter { !numbers.contains($0) })   // a panel can span screens
        }
        return numbers.compactMap { NSApp.window(withWindowNumber: $0) as? StickyPanel }
            .filter(\.isVisible)
    }

    private func onScreenWindows() -> [ScannedWindow] {
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return infos.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .infinite
            return ScannedWindow(
                number: number,
                pid: pid,
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                bounds: bounds
            )
        }
    }

    /// System UI that owns ordinary-looking windows and must not read as the boundary: the Dock owns
    /// layer-0 windows while Mission Control is up (observed in this app's own window-order logs), and
    /// WindowManager owns them under Stage Manager. Matched by bundle id, since the owner name in the
    /// window list is a process display name.
    private func systemUIPIDs(in windows: [ScannedWindow]) -> Set<pid_t> {
        let ids: Set<String> = ["com.apple.dock", "com.apple.WindowManager"]
        var result: Set<pid_t> = []
        for pid in Set(windows.map(\.pid)) {
            if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
               ids.contains(bundleID) {
                result.insert(pid)
            }
        }
        return result
    }

    /// `NSScreen.frame` in CoreGraphics display coordinates, to match the window list: AppKit's origin is
    /// the bottom-left of the primary screen with y up, CoreGraphics' is its top-left with y down.
    private func displayFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.frame }
        var frame = screen.frame
        frame.origin.y = primary.frame.height - screen.frame.maxY
        return frame
    }
}
