import CoreGraphics

public enum ExtensionLatencyCurve {
    public static func smoothedPath(points: [CGPoint], closed: Bool) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { path.addLine(to: first); if closed { path.closeSubpath() }; return path }
        guard points.count > 2 else { path.addLine(to: points[1]); if closed { path.closeSubpath() }; return path }
        let minimumY = points.map(\.y).min() ?? first.y
        let maximumY = points.map(\.y).max() ?? first.y
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : extrapolatedPoint(before: points[index], next: points[index + 1])
            let p1 = points[index]; let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : extrapolatedPoint(after: p2, previous: p1)
            let controls = cubicControls(p0: p0, p1: p1, p2: p2, p3: p3, minimumY: minimumY, maximumY: maximumY)
            path.addCurve(to: p2, control1: controls.0, control2: controls.1)
        }
        if closed { path.closeSubpath() }
        return path
    }
    private static func cubicControls(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, minimumY: CGFloat, maximumY: CGFloat) -> (CGPoint, CGPoint) {
        let t0: CGFloat = 0; let t1 = nextParameter(after: t0, from: p0, to: p1); let t2 = nextParameter(after: t1, from: p1, to: p2); let t3 = nextParameter(after: t2, from: p2, to: p3); let d = max(t2 - t1, .ulpOfOne)
        let a = vector(from: p0, to: p2, duration: max(t2 - t0, .ulpOfOne)); let b = vector(from: p1, to: p3, duration: max(t3 - t1, .ulpOfOne))
        var c1 = CGPoint(x: p1.x + a.dx * d / 3, y: p1.y + a.dy * d / 3); var c2 = CGPoint(x: p2.x - b.dx * d / 3, y: p2.y - b.dy * d / 3)
        c1.x = min(max(c1.x, min(p1.x,p2.x)), max(p1.x,p2.x)); c2.x = min(max(c2.x, min(p1.x,p2.x)), max(p1.x,p2.x)); c1.y = min(max(c1.y, minimumY), maximumY); c2.y = min(max(c2.y, minimumY), maximumY); return (c1,c2)
    }
    private static func nextParameter(after t: CGFloat, from a: CGPoint, to b: CGPoint) -> CGFloat { let x=b.x-a.x, y=b.y-a.y; return t + max(sqrt(sqrt(x*x+y*y)), .ulpOfOne) }
    private static func vector(from a: CGPoint, to b: CGPoint, duration: CGFloat) -> CGVector { CGVector(dx:(b.x-a.x)/duration,dy:(b.y-a.y)/duration) }
    private static func extrapolatedPoint(before a: CGPoint, next b: CGPoint) -> CGPoint { CGPoint(x:a.x-(b.x-a.x),y:a.y-(b.y-a.y)) }
    private static func extrapolatedPoint(after a: CGPoint, previous b: CGPoint) -> CGPoint { CGPoint(x:a.x+(a.x-b.x),y:a.y+(a.y-b.y)) }
}
