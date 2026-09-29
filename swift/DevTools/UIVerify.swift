import AppKit
import ApplicationServices

func attr(_ element: AXUIElement, _ key: String) -> AnyObject? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value
}
func walk(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 30 else { return [] }
    return [element] + ((attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap { walk($0, depth: depth + 1) }
}
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kun.bandwagon")
guard let app = apps.last else { print("FAIL app not running"); exit(1) }
let root = AXUIElementCreateApplication(app.processIdentifier)
var found = false
for el in walk(root) {
    let role = attr(el, kAXRoleAttribute) as? String ?? ""
    let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attr(el, $0) as? String }
    if role == kAXButtonRole, labels.contains("客户端") {
        found = AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
        break
    }
}
guard found else { print("FAIL clients navigation unavailable to AX"); exit(1) }
// Poll observable state rather than assuming a successful click or launch.
for _ in 0..<100 {
    let labels = walk(root).flatMap { el in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attr(el, $0) as? String } }
    if labels.contains(where: { $0.contains("3X-UI 已拒绝认证（HTTP 200，success:false），原因未确定") }) && labels.contains("连接失败") {
        guard !labels.contains("暂无客户端"), !labels.contains("暂无数据") else { print("FAIL false empty state visible"); exit(1) }
        print("PASS packaged app Clients view shows authentication error, not empty state")
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.1)
}
print("FAIL expected authentication state not observed")
exit(1)
