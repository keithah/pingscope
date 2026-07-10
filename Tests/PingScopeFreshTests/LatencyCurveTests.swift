import CoreGraphics
@testable import PingScopeCore
import XCTest

final class LatencyCurveTests: XCTestCase {
    func testSmoothedPathWithNoPointsIsEmpty() {
        let path = LatencyCurve.smoothedPath(points: [], closed: false)

        XCTAssertTrue(path.elements().isEmpty)
    }

    func testSmoothedPathWithOnePointIncludesDrawableZeroLengthLine() {
        let point = CGPoint(x: 12, y: 8)
        let elements = LatencyCurve.smoothedPath(points: [point], closed: false).elements()

        XCTAssertEqual(elements.map(\.kind), [.moveToPoint, .addLineToPoint])
        XCTAssertEqual(elements.map(\.endPoint), [point, point])
    }

    func testSmoothedPathWithTwoPointsStaysStraight() {
        let points = [CGPoint(x: 0, y: 10), CGPoint(x: 40, y: 20)]
        let elements = LatencyCurve.smoothedPath(points: points, closed: false).elements()

        XCTAssertEqual(elements.map(\.kind), [.moveToPoint, .addLineToPoint])
        XCTAssertEqual(elements.map(\.endPoint), points)
    }

    func testSmoothedPathPassesThroughInputSamplePoints() {
        let points = [
            CGPoint(x: 0, y: 40),
            CGPoint(x: 30, y: 12),
            CGPoint(x: 60, y: 34),
            CGPoint(x: 90, y: 18),
            CGPoint(x: 120, y: 30)
        ]
        let elements = LatencyCurve.smoothedPath(points: points, closed: false).elements()

        XCTAssertEqual(elements.first?.endPoint, points.first)
        XCTAssertEqual(elements.dropFirst().map(\.endPoint), Array(points.dropFirst()))
    }

    func testSmoothedPathControlPointsStayMonotonicAndInsidePointBounds() {
        let points = [
            CGPoint(x: 0, y: 48),
            CGPoint(x: 20, y: 8),
            CGPoint(x: 45, y: 42),
            CGPoint(x: 80, y: 12),
            CGPoint(x: 120, y: 36)
        ]
        let elements = LatencyCurve.smoothedPath(points: points, closed: false).elements()
        let controlPoints = elements.flatMap(\.points)
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!

        XCTAssertFalse(controlPoints.isEmpty)
        XCTAssertEqual(controlPoints.map(\.x), controlPoints.map(\.x).sorted())
        for point in controlPoints {
            XCTAssertGreaterThanOrEqual(point.y, minY - 0.001)
            XCTAssertLessThanOrEqual(point.y, maxY + 0.001)
        }
    }
}

private struct PathElement: Equatable {
    enum Kind: Equatable {
        case moveToPoint
        case addLineToPoint
        case addQuadCurveToPoint
        case addCurveToPoint
        case closeSubpath
    }

    let kind: Kind
    let points: [CGPoint]

    var endPoint: CGPoint? {
        points.last
    }
}

private extension CGPath {
    func elements() -> [PathElement] {
        var elements: [PathElement] = []
        applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                elements.append(PathElement(kind: .moveToPoint, points: [element.points[0]]))
            case .addLineToPoint:
                elements.append(PathElement(kind: .addLineToPoint, points: [element.points[0]]))
            case .addQuadCurveToPoint:
                elements.append(PathElement(kind: .addQuadCurveToPoint, points: [element.points[0], element.points[1]]))
            case .addCurveToPoint:
                elements.append(PathElement(kind: .addCurveToPoint, points: [element.points[0], element.points[1], element.points[2]]))
            case .closeSubpath:
                elements.append(PathElement(kind: .closeSubpath, points: []))
            @unknown default:
                break
            }
        }
        return elements
    }
}
