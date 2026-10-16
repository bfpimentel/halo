import AppKit
import Compositor
import JavaScriptCore
import Render

/// JS values → native types. Unknown or malformed values fall back to defaults and log, never throw.
@MainActor
enum Conversions {
    private static let defaults = Style()

    struct Attachment {
        var node: Int
        var side: Placement.Side
        var align: Placement.Alignment
        var offset: CGFloat
    }

    /// Surface props that matter to the runtime rather than to placement.
    struct SurfaceOptions {
        var name: String?
        var defaultHidden = false
        var attach: Attachment?
        var enter: Transition?
        var exit: Transition?
    }

    static func surfaceOptions(_ value: JSValue) -> SurfaceOptions {
        var options = SurfaceOptions()
        if let name = value.forProperty("name"), name.isString { options.name = name.toString() }
        options.defaultHidden = value.forProperty("defaultHidden")?.toBool() ?? false
        options.enter = value.forProperty("enter").flatMap { AnimationConversions.transition($0, key: "from") }
        options.exit = value.forProperty("exit").flatMap { AnimationConversions.transition($0, key: "to") }
        if let attach = value.forProperty("attach"), attach.isObject, let node = attach.forProperty("node"), node.isNumber {
            let side: Placement.Side = switch attach.forProperty("side")?.toString() {
            case "above": .above
            case "left": .left
            case "right": .right
            default: .below
            }
            let align: Placement.Alignment = switch attach.forProperty("align")?.toString() {
            case "center": .center
            case "end": .end
            default: .start
            }
            options.attach = Attachment(node: Int(node.toInt32()), side: side, align: align, offset: number(attach.forProperty("offset")) ?? 0)
        }
        return options
    }

    static func applyStyle(_ key: String, _ value: JSValue, to node: Node) {
        let present = !(value.isNull || value.isUndefined)
        switch key {
        case "flexDirection":
            node.style.flexDirection = value.toString() == "row" && present ? .row : defaults.flexDirection
        case "justify":
            node.style.justify = present ? justify(value.toString()) : defaults.justify
        case "align":
            node.style.align = present ? align(value.toString()) : defaults.align
        case "padding":
            node.style.padding = spacing(value) ?? defaults.padding
        case "gap":
            node.style.gap = number(value) ?? defaults.gap
        case "width":
            node.style.width = length(value)
        case "height":
            node.style.height = length(value)
        case "position":
            node.style.position = value.toString() == "absolute" && present ? .absolute : .relative
        case "top":
            node.style.top = length(value)
        case "right":
            node.style.right = length(value)
        case "bottom":
            node.style.bottom = length(value)
        case "left":
            node.style.left = length(value)
        case "grow":
            node.style.grow = number(value) ?? defaults.grow
        case "shrink":
            node.style.shrink = number(value) ?? defaults.shrink
        case "background":
            node.style.background = color(value)
        case "borderColor":
            node.style.borderColor = color(value)
        case "borderWidth":
            node.style.borderWidth = number(value) ?? defaults.borderWidth
        case "radius":
            node.style.radius = number(value) ?? defaults.radius
        case "opacity":
            node.style.opacity = Float(number(value) ?? CGFloat(defaults.opacity))
        case "scale":
            node.style.scale = number(value) ?? defaults.scale
        case "rotate":
            node.style.rotate = number(value) ?? defaults.rotate
        case "translateX":
            node.style.translateX = number(value) ?? defaults.translateX
        case "translateY":
            node.style.translateY = number(value) ?? defaults.translateY
        case "origin":
            let point = value.isArray ? value.toArray().compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } } : []
            node.style.originX = point.count == 2 ? point[0] : defaults.originX
            node.style.originY = point.count == 2 ? point[1] : defaults.originY
        case "transition":
            node.transitions = AnimationConversions.transitions(value)
        case "lines":
            guard let text = node as? Text else { return Log.warn("style.lines only applies to <Text>") }
            text.maxLines = number(value).map { max(0, Int($0)) } ?? 1
        case "textAlign":
            guard let text = node as? Text else { return Log.warn("style.textAlign only applies to <Text>") }
            text.alignment = switch value.toString() {
            case "center": .center
            case "right": .right
            default: .left
            }
        case "fill", "stroke", "track", "strokeWidth", "strokeStart", "strokeEnd", "lineCap", "lineJoin":
            guard let shape = node as? Shape else { return Log.warn("style.\(key) only applies to <Shape>") }
            applyShapeStyle(key, value, to: shape)
        case "color", "fontSize", "fontWeight", "fontFamily":
            if let text = node as? Text {
                applyTextStyle(key, value, font: &text.font, color: &text.color)
            } else if let input = node as? Input {
                applyTextStyle(key, value, font: &input.font, color: &input.color)
            } else {
                Log.warn("style.\(key) only applies to <Text> and <Input>")
            }
        default:
            Log.warn("unknown style key \"\(key)\"")
        }
    }

    private static func applyShapeStyle(_ key: String, _ value: JSValue, to shape: Shape) {
        switch key {
        case "fill": shape.fill = value.isUndefined || value.isNull ? .white : color(value)
        case "stroke": shape.stroke = color(value)
        case "track": shape.track = color(value)
        case "strokeWidth": shape.strokeWidth = number(value) ?? 1
        case "strokeStart": shape.strokeStart = min(1, max(0, number(value) ?? 0))
        case "strokeEnd": shape.strokeEnd = min(1, max(0, number(value) ?? 1))
        case "lineCap":
            shape.lineCap = switch value.toString() {
            case "round": .round
            case "square": .square
            default: .butt
            }
        default:
            shape.lineJoin = switch value.toString() {
            case "round": .round
            case "bevel": .bevel
            default: .miter
            }
        }
    }

    private static func applyTextStyle(_ key: String, _ value: JSValue, font: inout Font, color textColor: inout CGColor) {
        let base = Font()
        switch key {
        case "color": textColor = color(value) ?? .white
        case "fontSize": font.size = number(value) ?? base.size
        case "fontWeight": font.weight = weight(value) ?? base.weight
        default: font.family = value.isString ? value.toString() : nil
        }
    }

    static func applyProp(_ key: String, _ value: JSValue, to node: Node) {
        switch (node, key) {
        case (let text as Text, "text"):
            text.text = value.isString || value.isNumber ? value.toString() : ""
        case (let image as Image, "symbol"):
            image.source = value.isString ? .symbol(value.toString()) : nil
        case (let image as Image, "app"):
            image.source = value.isString ? .appIcon(bundleID: value.toString()) : nil
        case (let image as Image, "file"):
            image.source = value.isString ? .file(value.toString()) : nil
        case (let image as Image, "size"):
            image.size = number(value) ?? 16
        case (let image as Image, "color"):
            image.color = color(value)
        case (let shape as Shape, "path"):
            shape.path = value.isString ? value.toString() : ""
        case (let shape as Shape, "viewBox"):
            let size = value.isArray ? value.toArray().compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } } : []
            shape.viewBox = size.count == 2 ? CGSize(width: size[0], height: size[1]) : CGSize(width: 100, height: 100)
        case (let shape as Shape, "fit"):
            shape.fit = value.toString() == "stretch" ? .stretch : .contain
        case (let input as Input, "value"):
            input.value = value.isString ? value.toString() : ""
        case (let input as Input, "placeholder"):
            input.placeholder = value.isString ? value.toString() : ""
        case (let input as Input, "autofocus"):
            input.autofocus = value.toBool()
        case (_, "enter"):
            node.enter = AnimationConversions.transition(value, key: "from")
        case (_, "exit"):
            node.exit = AnimationConversions.transition(value, key: "to")
        default:
            Log.warn("unknown prop \"\(key)\" for \(type(of: node))")
        }
    }

    static func surfaceConfig(_ value: JSValue) -> SurfaceConfig {
        let screenID = value.forProperty("screen").map { $0.isNumber ? ScreenID($0.toUInt32()) : 0 } ?? 0
        var config = SurfaceConfig(screen: screenID)
        if let anchor = strings(value.forProperty("anchor")) {
            config.anchor = anchor.reduce(into: Edges()) { edges, name in
                switch name {
                case "top": edges.insert(.top)
                case "bottom": edges.insert(.bottom)
                case "left": edges.insert(.left)
                case "right": edges.insert(.right)
                default: Log.warn("unknown anchor \"\(name)\"")
                }
            }
        }
        if let margins = value.forProperty("margins"), let spacing = spacing(margins) {
            config.margins = Insets(top: spacing.top, right: spacing.right, bottom: spacing.bottom, left: spacing.left)
        }
        if let size = value.forProperty("size"), size.isObject {
            config.size = SurfaceSize(width: dimension(size.forProperty("width")), height: dimension(size.forProperty("height")))
        }
        switch value.forProperty("layer")?.toString() {
        case "desktop": config.layer = .desktop
        case "aboveMenu": config.layer = .aboveMenu
        case "overlay": config.layer = .overlay
        default: config.layer = .belowMenu
        }
        switch value.forProperty("input")?.toString() {
        case "hover": config.input = .hover
        case "interactive": config.input = .interactive
        case "keyboard": config.input = .keyboard
        default: config.input = .passthrough
        }
        if let avoid = strings(value.forProperty("avoid")) {
            if avoid.contains("notch") { config.avoid.insert(.notch) }
            if avoid.contains("menuBar") { config.avoid.insert(.menuBar) }
        }
        if let visible = value.forProperty("visible"), visible.isBoolean {
            config.visible = visible.toBool()
        }
        return config
    }

    static func screen(_ info: ScreenInfo) -> [String: Any] {
        [
            "id": Int(info.id),
            "name": info.name,
            "frame": rect(info.frame),
            "scale": info.scale,
            "index": info.index,
            "menuBarHeight": info.menuBarHeight,
            "notch": info.notch.map(rect) ?? NSNull(),
        ]
    }

    private static func rect(_ rect: CGRect) -> [String: Any] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    private static func number(_ value: JSValue?) -> CGFloat? {
        guard let value, value.isNumber else { return nil }
        return CGFloat(value.toDouble())
    }

    private static func strings(_ value: JSValue?) -> [String]? {
        guard let value, value.isArray else { return nil }
        return value.toArray().compactMap { $0 as? String }
    }

    private static func spacing(_ value: JSValue) -> Spacing? {
        if let all = number(value) { return Spacing(all) }
        guard value.isArray else { return nil }
        let values = value.toArray().compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } }
        switch values.count {
        case 2: return Spacing(vertical: values[0], horizontal: values[1])
        case 4: return Spacing(top: values[0], right: values[1], bottom: values[2], left: values[3])
        default:
            Log.warn("spacing must be a number, [vertical, horizontal] or [top, right, bottom, left]")
            return nil
        }
    }

    private static func length(_ value: JSValue) -> Length {
        if let points = number(value) { return .points(points) }
        if value.isString, let text = value.toString(), text.hasSuffix("%"), let percent = Double(text.dropLast()) {
            return .percent(CGFloat(percent))
        }
        return .auto
    }

    private static func dimension(_ value: JSValue?) -> Compositor.Dimension? {
        if let points = number(value) { return .fixed(points) }
        switch value?.toString() {
        case "fill": return .fill
        case "auto": return .auto
        default: return nil
        }
    }

    private static func justify(_ name: String) -> Justify {
        switch name {
        case "center": .center
        case "end": .end
        case "space-between": .spaceBetween
        case "space-around": .spaceAround
        case "space-evenly": .spaceEvenly
        default: .start
        }
    }

    private static func align(_ name: String) -> Align {
        switch name {
        case "start": .start
        case "center": .center
        case "end": .end
        default: .stretch
        }
    }

    private static func weight(_ value: JSValue) -> NSFont.Weight? {
        if let number = number(value) {
            let table: [(CGFloat, NSFont.Weight)] = [
                (100, .ultraLight), (200, .thin), (300, .light), (400, .regular), (500, .medium),
                (600, .semibold), (700, .bold), (800, .heavy), (900, .black),
            ]
            return table.min { abs($0.0 - number) < abs($1.0 - number) }?.1
        }
        switch value.toString() {
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return nil
        }
    }

    static func color(_ value: JSValue) -> CGColor? {
        guard value.isString, let raw = value.toString() else { return nil }
        if raw == "transparent" { return nil }
        var hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let packed = UInt64(hex, radix: 16) else {
            Log.warn("invalid color \"\(raw)\" (use #rgb, #rrggbb or #rrggbbaa)")
            return nil
        }
        let rgba = hex.count == 6 ? packed << 8 | 0xff : packed
        return CGColor(
            srgbRed: CGFloat((rgba >> 24) & 0xff) / 255,
            green: CGFloat((rgba >> 16) & 0xff) / 255,
            blue: CGFloat((rgba >> 8) & 0xff) / 255,
            alpha: CGFloat(rgba & 0xff) / 255
        )
    }
}
