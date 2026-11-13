import Foundation
@main struct StateRegression {
 @MainActor static func main() async {
   guard (try? SecureURLPolicy.baseURL(from: "https://example.com/panel")) != nil,
         (try? SecureURLPolicy.baseURL(from: "http://127.0.0.1:2053")) != nil else {
     print("FAIL HTTPS and loopback HTTP must remain valid")
     exit(1)
   }
   do {
     _ = try SecureURLPolicy.baseURL(from: "http://example.com/panel")
     print("FAIL public cleartext service URLs must be rejected")
     exit(1)
   } catch {
     // Expected: credentials must never be sent over public cleartext HTTP.
   }

   guard let norm1 = try? XUIClient.normalizedBaseURLString(from: "https://example.com:2053/panel"),
         norm1 == "https://example.com:2053",
         let norm2 = try? XUIClient.normalizedBaseURLString(from: "https://example.com:2053/panel/inbounds/"),
         norm2 == "https://example.com:2053",
         let norm3 = try? XUIClient.normalizedBaseURLString(from: "https://example.com:2053/custom/panel/"),
         norm3 == "https://example.com:2053/custom" else {
     print("FAIL panel BaseURL normalization must strip /panel and subroutes")
     exit(1)
   }
   print("PASS 3X-UI base URL normalization strips redundant /panel and subpaths")

   let model = AppModel()
   model.settings = AppSettings()
   model.settings.xuiBaseUrl = "http://127.0.0.1:1"
   model.settings.xuiUsername = "fixture"
   model.settings.xuiPassword = "fixture"
   await model.load()
   guard model.error != nil, model.overview.xui?.clients == nil else {
     print("FAIL connection failure must surface an error, not an empty clients array")
     exit(1)
   }
   print("PASS connection failure surfaces error without false-empty clients")

   let previous = model.settings
   var changed = previous
   changed.bwhVeid = "fixture-not-persisted"
   let configDir = FileManager.default.homeDirectoryForCurrentUser
     .appendingPathComponent("Library/Application Support/Bandwagon", isDirectory: true)
   var priorPermissions: [FileAttributeKey: Any]?
   if FileManager.default.fileExists(atPath: configDir.path) {
     priorPermissions = try? FileManager.default.attributesOfItem(atPath: configDir.path)
   }
   defer {
     if let priorPermissions {
       try? FileManager.default.setAttributes(priorPermissions, ofItemAtPath: configDir.path)
     }
   }
   // Keychain persistence is best-effort outside Bandwagon.app; block settings.json instead.
   try? FileManager.default.setAttributes(
     [.posixPermissions: NSNumber(value: Int16(0o500))],
     ofItemAtPath: configDir.path
   )
   let saved = await model.saveSettings(changed)
   guard !saved, model.settings == previous else {
     print("FAIL rejected secure save must leave active settings unchanged")
     exit(1)
   }
   print("PASS failed credential save does not replace active settings")
 }
}
