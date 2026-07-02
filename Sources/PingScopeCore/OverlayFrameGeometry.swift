import CoreGraphics
import Foundation

/// Pure geometry behind the app's overlay frame constraining. A borderless
/// window is exempt from AppKit's automatic frame constraining, so a persisted
/// overlay frame can be entirely off-screen after a display-configuration
/// change; the overlay then reads as enabled while nothing is visible.
///
/// Returns `nil` when `frame` already shows at least `minVisible` points on one
/// of `screens` (no move needed). Otherwise returns the frame clamped into the
/// first screen in `screens` -- callers put the preferred screen first. A frame
/// larger than the target screen is pinned to the screen's origin so its
/// top-left content stays reachable.
public func clampedOverlayFrame(
    _ frame: CGRect,
    into screens: [CGRect],
    minVisible: CGSize
) -> CGRect? {
    guard let target = screens.first else { return nil }
    let sufficientlyVisible = screens.contains { screen in
        let overlap = frame.intersection(screen)
        return overlap.width >= minVisible.width && overlap.height >= minVisible.height
    }
    guard !sufficientlyVisible else { return nil }
    var clamped = frame
    clamped.origin.x = min(max(frame.origin.x, target.minX), max(target.maxX - frame.width, target.minX))
    clamped.origin.y = min(max(frame.origin.y, target.minY), max(target.maxY - frame.height, target.minY))
    return clamped
}
