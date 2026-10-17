import SwiftUI

/// One of the Finance UI Kit's icons, kept as the path data the kit exports (`tools/kit-icons/icons.json`, turned
/// into `KitIcons.swift` by `icons_to_swift.py`). Draw it with `KitIconView`.
struct KitIcon: Sendable {
    /// A colour the kit's icon used, as a role so the icon follows light and dark mode.
    enum Role: Sendable {
        /// The kit's black letters and icons (white in dark mode).
        case ink
        /// The near-white the kit uses on its blue tiles.
        case light
        /// One of the tile blues (the generator drops the tile itself; this only appears if it didn't).
        case tile
        case hex(String)
    }

    struct Element: Sendable {
        let path: Path
        let fill: Role?
        let stroke: Role?
        let lineWidth: CGFloat
        let cap: CGLineCap
        let join: CGLineJoin
        let evenOdd: Bool

        init(
            d: String, fill: Role? = nil, stroke: Role? = nil, lineWidth: CGFloat = 1, cap: CGLineCap = .butt,
            join: CGLineJoin = .miter, evenOdd: Bool = false
        ) {
            path = SVGPath.path(from: d)
            self.fill = fill
            self.stroke = stroke
            self.lineWidth = lineWidth
            self.cap = cap
            self.join = join
            self.evenOdd = evenOdd
        }
    }

    let width: CGFloat
    let height: CGFloat
    let elements: [Element]
}

/// Draws a `KitIcon` scaled to `height`. With `color` every element is drawn in that one colour (white on a
/// tile, ink in the nav bar); without it the kit's own colours apply, mapped to the current appearance.
struct KitIconView: View {
    let icon: KitIcon
    var height: CGFloat = 24
    var color: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / icon.width, size.height / icon.height)
            context.translateBy(x: (size.width - icon.width * scale) / 2, y: (size.height - icon.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for element in icon.elements {
                if let fill = element.fill {
                    context.fill(
                        element.path, with: .color(resolve(fill)),
                        style: FillStyle(eoFill: element.evenOdd)
                    )
                }
                if let stroke = element.stroke {
                    context.stroke(
                        element.path, with: .color(resolve(stroke)),
                        style: StrokeStyle(lineWidth: element.lineWidth, lineCap: element.cap, lineJoin: element.join)
                    )
                }
            }
        }
        .frame(width: height * icon.width / icon.height, height: height)
        .accessibilityHidden(true)
    }

    private func resolve(_ role: KitIcon.Role) -> Color {
        if let color { return color }
        switch role {
        case .ink: return KitColor.label.resolved(for: scheme)
        case .light: return KitColor.white
        case .tile: return KitColor.accent.resolved(for: scheme)
        case .hex(let value): return Color(kitHex: value)
        }
    }
}

/// The path subset the kit's icons use: absolute M, L, H, V, C and Z.
enum SVGPath {
    static func path(from d: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func consume(_ count: Int) -> [CGFloat]? {
            guard numbers.count >= count else { return nil }
            defer { numbers.removeFirst(count) }
            return Array(numbers.prefix(count))
        }

        func run() {
            while true {
                switch command {
                case "M":
                    guard let n = consume(2) else { return }
                    current = CGPoint(x: n[0], y: n[1])
                    start = current
                    path.move(to: current)
                    command = "L"
                case "L":
                    guard let n = consume(2) else { return }
                    current = CGPoint(x: n[0], y: n[1])
                    path.addLine(to: current)
                case "H":
                    guard let n = consume(1) else { return }
                    current.x = n[0]
                    path.addLine(to: current)
                case "V":
                    guard let n = consume(1) else { return }
                    current.y = n[0]
                    path.addLine(to: current)
                case "C":
                    guard let n = consume(6) else { return }
                    current = CGPoint(x: n[4], y: n[5])
                    path.addCurve(
                        to: current, control1: CGPoint(x: n[0], y: n[1]), control2: CGPoint(x: n[2], y: n[3])
                    )
                default:
                    numbers.removeAll()
                    return
                }
            }
        }

        var token = ""
        func flushNumber() {
            if !token.isEmpty, token != "-", token != ".", let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        for character in d {
            switch character {
            case "M", "L", "H", "V", "C", "Z":
                flushNumber()
                run()
                if character == "Z" {
                    path.closeSubpath()
                    current = start
                } else {
                    command = character
                }
            case " ", ",", "\n", "\t":
                flushNumber()
            case "-":
                flushNumber()
                token = "-"
            case ".":
                // A second "." starts a new number ("1.5.5" is 1.5 and .5).
                if token.contains(".") { flushNumber() }
                token.append(".")
            default:
                token.append(character)
            }
        }
        flushNumber()
        run()
        return path
    }
}
