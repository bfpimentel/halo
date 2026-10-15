// Prints "<window id> <x> <y> <width> <height>" for every on-screen window of a process (top-left points).
// Usage: swift scripts/window-ids.swift <pid>
import CoreGraphics

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    fatalError("usage: window-ids.swift <pid>")
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Double]
    else { continue }
    let values = ["X", "Y", "Width", "Height"].map { Int(bounds[$0] ?? 0) }
    print(id, values.map(String.init).joined(separator: " "))
}
