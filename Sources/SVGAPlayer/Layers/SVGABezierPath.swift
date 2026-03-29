import UIKit

@MainActor
final class SVGABezierPath: UIBezierPath {
    private var displaying = false
    private var backValues: String = ""

    private static let maxPathLength = 100_000

    func setValues(_ values: String) {
        guard displaying else {
            backValues = values
            return
        }
        guard values.count <= Self.maxPathLength else { return }
        let validMethods: Set<Character> = ["M","L","H","V","C","S","Q","R","A","Z",
                                             "m","l","h","v","c","s","q","r","a","z"]
        var method: String?
        var argBuffer = ""

        func flush() {
            guard let m = method else { return }
            let trimmed = argBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let args = trimmed.isEmpty ? [] : trimmed.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            operate(method: m, args: args)
            argBuffer = ""
        }

        for ch in values {
            if validMethods.contains(ch) {
                flush()
                method = String(ch)
            } else {
                if ch == "," {
                    argBuffer.append(" ")
                } else {
                    argBuffer.append(ch)
                }
            }
        }
        flush()
    }

    func createLayer() -> CAShapeLayer {
        if !displaying {
            displaying = true
            setValues(backValues)
        }
        let layer = CAShapeLayer()
        layer.path = cgPath
        layer.fillColor = UIColor.black.cgColor
        return layer
    }

    private func operate(method: String, args: [String]) {
        let rel = method == method.lowercased()
        switch method.uppercased() {
        case "M" where args.count == 2:
            let p = argPoint(CGPoint(x: f(args[0]), y: f(args[1])), relative: rel)
            move(to: p)
        case "L" where args.count == 2:
            let p = argPoint(CGPoint(x: f(args[0]), y: f(args[1])), relative: rel)
            addLine(to: p)
        case "C" where args.count == 6:
            let cp1 = argPoint(CGPoint(x: f(args[0]), y: f(args[1])), relative: rel)
            let cp2 = argPoint(CGPoint(x: f(args[2]), y: f(args[3])), relative: rel)
            let end = argPoint(CGPoint(x: f(args[4]), y: f(args[5])), relative: rel)
            addCurve(to: end, controlPoint1: cp1, controlPoint2: cp2)
        case "Q" where args.count == 4:
            let cp = argPoint(CGPoint(x: f(args[0]), y: f(args[1])), relative: rel)
            let end = argPoint(CGPoint(x: f(args[2]), y: f(args[3])), relative: rel)
            addQuadCurve(to: end, controlPoint: cp)
        case "H" where args.count == 1:
            let x = f(args[0]) + (rel ? currentPoint.x : 0)
            addLine(to: CGPoint(x: x, y: currentPoint.y))
        case "V" where args.count == 1:
            let y = f(args[0]) + (rel ? currentPoint.y : 0)
            addLine(to: CGPoint(x: currentPoint.x, y: y))
        case "Z":
            close()
        default:
            break
        }
    }

    private func f(_ s: String) -> CGFloat { CGFloat((s as NSString).floatValue) }

    private func argPoint(_ point: CGPoint, relative: Bool) -> CGPoint {
        guard relative else { return point }
        return CGPoint(x: point.x + currentPoint.x, y: point.y + currentPoint.y)
    }
}
