import AppKit

/// Draws the little menu bar graphics. Pass `color: nil` for template rendering (macOS tints it to match
/// the menu bar); pass a colour for a fixed-colour, non-template image.
enum WidgetRenderer {
    static func symbol(_ name: String, pointSize: CGFloat = 12) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    static func tinted(_ image: NSImage?, _ color: NSColor?) -> NSImage? {
        guard let image, let color else { return image }
        let out = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        out.isTemplate = false
        return out
    }

    static func sparkline(values: [Double], range: ClosedRange<Double>?, color: NSColor?,
                          size: NSSize = NSSize(width: 30, height: 14)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let ink = color ?? .black
            guard values.count > 1 else {
                ink.withAlphaComponent(0.35).setStroke()
                let base = NSBezierPath()
                base.move(to: NSPoint(x: 0, y: 1))
                base.line(to: NSPoint(x: rect.width, y: 1))
                base.lineWidth = 1
                base.stroke()
                return true
            }
            let lo = range?.lowerBound ?? (values.min() ?? 0)
            var hi = range?.upperBound ?? (values.max() ?? 1)
            if hi - lo < 1 { hi = lo + 1 }
            let step = rect.width / CGFloat(values.count - 1)
            func point(_ i: Int) -> NSPoint {
                let n = min(max((values[i] - lo) / (hi - lo), 0), 1)
                return NSPoint(x: CGFloat(i) * step, y: 1 + CGFloat(n) * (rect.height - 2))
            }
            let line = NSBezierPath()
            line.move(to: point(0))
            for i in 1..<values.count { line.line(to: point(i)) }

            let area = line.copy() as! NSBezierPath
            area.line(to: NSPoint(x: rect.width, y: 0))
            area.line(to: NSPoint(x: 0, y: 0))
            area.close()
            ink.withAlphaComponent(0.22).setFill()
            area.fill()

            ink.setStroke()
            line.lineWidth = 1.3
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            line.stroke()
            return true
        }
        image.isTemplate = (color == nil)
        return image
    }

    /// Vertical level bar, `fraction` 0...1.
    static func bar(fraction: Double, color: NSColor?, size: NSSize = NSSize(width: 7, height: 14)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let ink = color ?? .black
            let track = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            ink.withAlphaComponent(0.28).setFill()
            track.fill()
            let h = max(2, CGFloat(min(max(fraction, 0), 1)) * (rect.height - 1))
            let fill = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: rect.width - 1, height: h), xRadius: 2, yRadius: 2)
            ink.setFill()
            fill.fill()
            return true
        }
        image.isTemplate = (color == nil)
        return image
    }

    static func title(_ text: String, color: NSColor? = nil) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ]
        if let color { attributes[.foregroundColor] = color }
        return NSAttributedString(string: " " + text, attributes: attributes)
    }
}
