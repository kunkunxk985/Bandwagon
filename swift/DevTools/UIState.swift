import AppKit
import ApplicationServices
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kun.bandwagon")
print("app_count=\(apps.count) ax_trusted=\(AXIsProcessTrusted())")
for app in apps {
 let root = AXUIElementCreateApplication(app.processIdentifier)
 var windows: CFTypeRef?
 let status = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
 print("window_read_status=\(status.rawValue) window_count=\((windows as? [AXUIElement])?.count ?? 0)")
}
