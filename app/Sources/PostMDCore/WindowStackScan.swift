import CoreGraphics

/// One on-screen window, reduced to what a stacking scan needs. Mirrors the fields of a
/// `CGWindowListCopyWindowInfo` entry so the scan itself stays free of CoreGraphics calls and testable.
public struct ScannedWindow: Equatable {
    public let number: Int
    public let pid: Int32
    public let layer: Int
    public let alpha: Double
    /// CoreGraphics display coordinates: origin at the top-left of the primary display, y growing down.
    public let bounds: CGRect

    public init(number: Int, pid: Int32, layer: Int, alpha: Double, bounds: CGRect) {
        self.number = number
        self.pid = pid
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }
}

public enum WindowStackScan {
    /// Our windows on `screen` that sit above every other app's windows there, front to back.
    ///
    /// The caller hands in the window list front-to-back; the walk stops at the first window belonging to
    /// another app, because everything past it is already covered.
    ///
    /// - Parameters:
    ///   - screen: in the same coordinate space as `ScannedWindow.bounds`. Windows that miss it are
    ///     skipped rather than treated as the boundary: another display's stacking is its own business,
    ///     and letting a window over there end the walk would silently shrink the result.
    ///   - ignoredPIDs: system UI that owns ordinary-looking windows — the Dock owns layer-0 windows
    ///     while Mission Control is up (observed), and WindowManager owns them under Stage Manager.
    ///     Treating either as the boundary would cut the walk short exactly when it matters.
    ///   - maxLayer: window levels above this are chrome (menu bar, Dock icons) and never participate.
    public static func windowNumbersAboveOtherApps(
        in windows: [ScannedWindow],
        ourPID: Int32,
        screen: CGRect,
        ignoredPIDs: Set<Int32> = [],
        maxLayer: Int = 3
    ) -> [Int] {
        var result: [Int] = []
        for window in windows {
            guard window.layer <= maxLayer,
                  window.alpha > 0.01,                  // invisible helper windows
                  window.bounds.intersects(screen)
            else { continue }

            if window.pid == ourPID {
                result.append(window.number)
            } else if !ignoredPIDs.contains(window.pid) {
                break
            }
        }
        return result
    }
}
