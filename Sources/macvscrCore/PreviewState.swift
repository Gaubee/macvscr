import Foundation
import Combine

/// Global, in-memory preview state. Singleton and nullable-by-design (per the
/// spec): when `active` is non-nil, the live display is temporarily showing a
/// preview preset and a timer will revert it.
///
/// Owned by `TrayController`, which mutates it. Observable so the management
/// window (SwiftUI) can show the live countdown / "Previewing…" indicator.
public final class PreviewState: ObservableObject {

    public static let shared = PreviewState()

    /// Default preview window before auto-reverting to the committed config.
    public static let defaultDuration: TimeInterval = 10

    /// What's currently being previewed, if anything. Mutating `active` does
    /// NOT, by itself, reconfigure the display — callers go through
    /// `TrayController.startPreview`, which sets this and arms the timer.
    @Published public var active: CustomPreset?

    /// Wall-clock time the current preview began (for countdown display).
    @Published private(set) public var startedAt: Date?

    /// How long the preview lasts before auto-reverting.
    @Published private(set) public var duration: TimeInterval = defaultDuration

    private var timer: DispatchSourceTimer?
    private var tickTimer: DispatchSourceTimer?

    private init() {}

    // MARK: Arming / clearing (called only from TrayController)

    /// (Re)arm the preview timer. On expiry, `onExpire` is fired once. The
    /// 1Hz `onTick` is for live countdown UI.
    public func arm(duration: TimeInterval = defaultDuration,
             onExpire: @escaping () -> Void,
             onTick: @escaping () -> Void) {
        cancelTimer()
        self.duration = duration
        startedAt = Date()

        let q = DispatchQueue.main
        let fire = DispatchSource.makeTimerSource(queue: q)
        fire.schedule(deadline: .now() + duration)
        fire.setEventHandler(handler: onExpire)
        fire.resume()
        timer = fire

        let tick = DispatchSource.makeTimerSource(queue: q)
        tick.schedule(deadline: .now() + 1, repeating: 1)
        tick.setEventHandler(handler: onTick)
        tick.resume()
        tickTimer = tick
    }

    /// Clear the preview and stop any timer. Does NOT touch the display.
    public func clear() {
        cancelTimer()
        active = nil
        startedAt = nil
    }

    /// Seconds remaining in the current preview (clamped ≥ 0); nil if inactive.
    public var secondsRemaining: Int? {
        guard let start = startedAt else { return nil }
        return max(0, Int(duration - Date().timeIntervalSince(start)))
    }

    private func cancelTimer() {
        timer?.cancel(); timer = nil
        tickTimer?.cancel(); tickTimer = nil
    }
}
