import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print("num=\(w[kCGWindowNumber as String] ?? 0) layer=\(w[kCGWindowLayer as String] ?? 0) onscreen=\(w[kCGWindowIsOnscreen as String] ?? false) alpha=\(w[kCGWindowAlpha as String] ?? 0) bounds=\(b["X"]!),\(b["Y"]!) \(b["Width"]!)x\(b["Height"]!) name=\(w[kCGWindowName as String] ?? "-")")
}
print("--- screens:")
for i in 0..<CGDisplayCount() { }
var cnt: UInt32 = 0; var ids = [CGDirectDisplayID](repeating: 0, count: 8); CGGetActiveDisplayList(8, &ids, &cnt)
for i in 0..<Int(cnt) { print("display \(ids[i]) bounds=\(CGDisplayBounds(ids[i]))") }
