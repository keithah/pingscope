import CoreGraphics
import PingScopeCore
import PingScopeExtensionSupport
import XCTest

final class ExtensionLatencyCurveParityTests: XCTestCase {
    func testSupportCurveMatchesCoreControlGeometryForRepresentativeAndDegenerateInputs() {
        for points in [
            [] as [CGPoint],
            [CGPoint(x: 1, y: 2)],
            [CGPoint(x: 0, y: 4), CGPoint(x: 8, y: 1)],
            [CGPoint(x: 0, y: 8), CGPoint(x: 4, y: 1), CGPoint(x: 9, y: 7), CGPoint(x: 13, y: 2)]
        ] {
            XCTAssertEqual(elements(of: LatencyCurve.smoothedPath(points: points, closed: false)), elements(of: ExtensionLatencyCurve.smoothedPath(points: points, closed: false)))
        }
    }

    private func elements(of path: CGPath) -> [String] {
        var result: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = (0..<(element.type == .addCurveToPoint ? 3 : element.type == .addQuadCurveToPoint ? 2 : 1)).map { index in
                let point = element.points[index]
                return "\(point.x),\(point.y)"
            }.joined(separator: ";")
            result.append("\(element.type.rawValue):\(points)")
        }
        return result
    }
}
