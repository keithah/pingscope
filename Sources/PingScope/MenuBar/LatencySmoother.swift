import Foundation

struct LatencySmoother: Sendable {
    let alpha: Double
    let maxStepMS: Double

    init(alpha: Double = 0.35, maxStepMS: Double = 40) {
        self.alpha = alpha
        self.maxStepMS = maxStepMS
    }

    func next(previousMS: Double?, rawMS: Double?) -> Double? {
        guard let rawMS else {
            return nil
        }

        guard let previousMS else {
            return rawMS
        }

        let ema = (alpha * rawMS) + ((1 - alpha) * previousMS)
        let delta = ema - previousMS

        if abs(delta) <= maxStepMS {
            return ema
        }

        let boundedDelta = delta.sign == .minus ? -maxStepMS : maxStepMS
        return previousMS + boundedDelta
    }
}
