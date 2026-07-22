import Foundation

public enum MonitoringVisibility: Sendable, Equatable {
    case activeUI
    case idleForeground
    case background
}

public enum PowerSource: Sendable, Equatable {
    case ac
    case battery
    case unknown
}

public enum ThermalTier: Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
}

/// Environment inputs that scale probe cadence. Reported by platform monitors;
/// consumed by ``MeasurementScheduler``. Core stays platform-agnostic — nothing
/// here imports AppKit/UIKit/IOKit.
public struct CadenceInputs: Sendable, Equatable {
    public var visibility: MonitoringVisibility
    public var powerSource: PowerSource
    public var isLowPowerMode: Bool
    public var thermalTier: ThermalTier

    public init(
        visibility: MonitoringVisibility = .activeUI,
        powerSource: PowerSource = .unknown,
        isLowPowerMode: Bool = false,
        thermalTier: ThermalTier = .nominal
    ) {
        self.visibility = visibility
        self.powerSource = powerSource
        self.isLowPowerMode = isLowPowerMode
        self.thermalTier = thermalTier
    }

    /// All-nominal: multiplier 1.0, i.e. today's fixed cadence.
    public static let `default` = CadenceInputs()

    /// The most-conservative axis wins. Taking the max (rather than the product)
    /// keeps the multiplier bounded and predictable, and is trivial to reason
    /// about in tests. Ceiling clamping in ``effectiveInterval(base:ceiling:)``
    /// still guards the combined worst case.
    public var multiplier: Double {
        let visibilityFactor: Double
        switch visibility {
        case .activeUI: visibilityFactor = 1
        case .idleForeground: visibilityFactor = 2
        case .background: visibilityFactor = 4
        }
        let powerFactor: Double
        switch powerSource {
        case .ac, .unknown: powerFactor = 1
        case .battery: powerFactor = 2
        }
        let lowPowerFactor: Double = isLowPowerMode ? 4 : 1
        let thermalFactor: Double
        switch thermalTier {
        case .nominal, .fair: thermalFactor = 1
        case .serious: thermalFactor = 4
        case .critical: thermalFactor = 8
        }
        return max(visibilityFactor, powerFactor, lowPowerFactor, thermalFactor)
    }

    /// Effective interval for a host whose configured interval is `base`.
    /// Floored at `base` (never faster than the user asked). Adaptive scaling
    /// is capped at `ceiling` when the configured base does not already exceed it.
    public func effectiveInterval(base: Duration, ceiling: Duration = .seconds(300)) -> Duration {
        let scaled = base.seconds * multiplier
        let clamped = max(base.seconds, min(scaled, ceiling.seconds))
        return .seconds(clamped)
    }

    /// Reduces raw platform signals to a single set of inputs. Visibility is the
    /// most-conservative of: an obscured screen (asleep/locked) forces
    /// `.background`; a backgrounded app is `.background`; visible live UI is
    /// `.activeUI`; otherwise `.idleForeground`.
    public static func combining(
        screenObscured: Bool,
        uiVisible: Bool,
        appBackgrounded: Bool,
        powerSource: PowerSource,
        isLowPowerMode: Bool,
        thermalTier: ThermalTier
    ) -> CadenceInputs {
        let visibility: MonitoringVisibility
        if screenObscured || appBackgrounded {
            visibility = .background
        } else if uiVisible {
            visibility = .activeUI
        } else {
            visibility = .idleForeground
        }
        return CadenceInputs(
            visibility: visibility,
            powerSource: powerSource,
            isLowPowerMode: isLowPowerMode,
            thermalTier: thermalTier
        )
    }
}
