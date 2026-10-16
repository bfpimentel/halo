import AppKit
import Testing
@testable import Render

@MainActor
@Suite struct ShapeTests {
    private enum Element: Equatable {
        case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), curve(CGPoint, CGPoint, CGPoint), close
    }

    private func elements(_ data: String) -> [Element] {
        var result: [Element] = []
        PathData.parse(data).applyWithBlock { pointer in
            let element = pointer.pointee
            let p = element.points
            switch element.type {
            case .moveToPoint: result.append(.move(p[0]))
            case .addLineToPoint: result.append(.line(p[0]))
            case .addQuadCurveToPoint: result.append(.quad(p[0], p[1]))
            case .addCurveToPoint: result.append(.curve(p[0], p[1], p[2]))
            case .closeSubpath: result.append(.close)
            @unknown default: break
            }
        }
        return result
    }

    private func near(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 0.5) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    @Test func relativeAndImplicitCommands() {
        #expect(elements("m10 10 20 0 v10 h-20 z") == [
            .move(CGPoint(x: 10, y: 10)), .line(CGPoint(x: 30, y: 10)), .line(CGPoint(x: 30, y: 20)),
            .line(CGPoint(x: 10, y: 20)), .close,
        ])
    }

    @Test func compactNumbers() {
        #expect(elements("M0,0L10-5.5.5.5 1e1 2E0") == [
            .move(.zero), .line(CGPoint(x: 10, y: -5.5)), .line(CGPoint(x: 0.5, y: 0.5)), .line(CGPoint(x: 10, y: 2)),
        ])
    }

    @Test func smoothCurvesReflectThePreviousControlPoint() {
        let path = elements("M0 0 C 0 10 10 10 10 0 S 20 -10 20 0")
        #expect(path.last == .curve(CGPoint(x: 10, y: -10), CGPoint(x: 20, y: -10), CGPoint(x: 20, y: 0)))
    }

    @Test func arcsTraceTheirEllipse() {
        #expect(near(PathData.parse("M 50 0 A 50 50 0 1 1 50 100 A 50 50 0 1 1 50 0").boundingBoxOfPath, CGRect(x: 0, y: 0, width: 100, height: 100)))
        // Radii too small for the endpoints are scaled up: a half circle of radius 5 (y grows downwards, sweep 1 goes up).
        #expect(near(PathData.parse("M0 0 A 1 1 0 0 1 10 0").boundingBoxOfPath, CGRect(x: 0, y: -5, width: 10, height: 5)))
        if case .curve(_, _, let end) = elements("M 0 50 A 50 50 0 0 1 50 0").last { #expect(end == CGPoint(x: 50, y: 0)) }
    }

    @Test func malformedDataKeepsWhatParsed() {
        #expect(elements("M 0 0 L 10 10 L 5") == [.move(.zero), .line(CGPoint(x: 10, y: 10))])
    }

    @Test func fitContainsOrStretchesInsideTheStrokeInset() {
        let box = CGSize(width: 40, height: 20)
        let contain = Shape.transform(viewBox: CGSize(width: 100, height: 100), into: box, fit: .contain, inset: 2)
        #expect(CGRect(x: 0, y: 0, width: 100, height: 100).applying(contain) == CGRect(x: 12, y: 2, width: 16, height: 16))
        let stretch = Shape.transform(viewBox: CGSize(width: 100, height: 100), into: box, fit: .stretch, inset: 0)
        #expect(CGRect(x: 0, y: 0, width: 100, height: 100).applying(stretch) == CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    @Test func layoutRefitsThePath() {
        let shape = Shape(style: Style(width: .points(40), height: .points(20)))
        shape.path = "M 0 0 L 100 100"
        shape.fit = .stretch
        let root = RenderRoot(node: shape, hostLayer: CALayer(), size: CGSize(width: 200, height: 200), contentsScale: 2)
        root.layoutNow()
        let fitted = (shape.layer as? CAShapeLayer)?.path?.boundingBoxOfPath
        #expect(fitted == CGRect(x: 0, y: 0, width: 40, height: 20))
        shape.style.width = .points(80)
        root.layoutNow()
        #expect((shape.layer as? CAShapeLayer)?.path?.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 80, height: 20))
    }
}
