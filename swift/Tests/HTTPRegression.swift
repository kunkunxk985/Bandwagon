import Foundation
@main struct HTTPRegression {
 @MainActor static func main() async {
   var settings = AppSettings()
   settings.xuiBaseUrl = "http://127.0.0.1:" + CommandLine.arguments[1] + "/private"
   settings.xuiUsername = "fixture"
   settings.xuiPassword = "p&+= fixture"
   settings.xuiTwoFactor = "123456"
   let expected = CommandLine.arguments[2]
   if expected == "concurrency" {
     settings.bwhApiBase = "http://127.0.0.1:" + CommandLine.arguments[1] + "/bwh"
     settings.bwhVeid = "fixture"; settings.bwhApiKey = "fixture"
     let model = AppModel(); model.settings = settings
     let first = Task { await model.load() }
     let second = Task { await model.load() }
     try? await Task.sleep(for: .milliseconds(500))
     guard model.overview.xui?.clients?.count == 1, !model.xuiLoading, model.bwhLoading else {
       print("FAIL XUI must publish before slow BWH completes"); exit(1)
     }
     await first.value; await second.value
     guard !model.loading, model.overview.xui?.error == nil, model.overview.bwh?.error != nil else {
       print("FAIL independent service errors/loading"); exit(1)
     }
     print("PASS concurrent refresh publishes XUI before BWH; independent errors/loading")
     return
   }
   if expected == "writes" || expected == "write-reject" {
     do {
       let overview = try await XUIClient.fetch(settings)
       guard let client = overview.clients?.first, client.subId == "sub-fixture" else {
         print("FAIL client must carry its subId"); exit(1)
       }
       if expected == "write-reject" {
         do {
           try await XUIClient.updateClient(settings, client: client, changes: ClientChanges(enable: false))
           print("FAIL a skipped client must throw"); exit(1)
         } catch {
           guard XUIError.safeMessage(error).contains("fixture refused") else {
             print("FAIL the panel's refusal reason must reach the user: \(XUIError.safeMessage(error))"); exit(1)
           }
         }
         print("PASS refused client write surfaces the panel's reason")
         return
       }
       // Quota + expiry: read the record, send it back as ToClient would, edited.
       try await XUIClient.updateClient(
         settings, client: client,
         changes: ClientChanges(totalBytes: 50 * 1_073_741_824, expiryTime: 1_893_456_000_000)
       )
       // Enable alone must not rewrite the record.
       try await XUIClient.updateClient(settings, client: client, changes: ClientChanges(enable: false))
       try await XUIClient.resetTraffic(settings, client: client)
       guard try await XUIClient.subscriptionBase(settings) == "https://sub.example/sub/" else {
         print("FAIL subscription base must come from setting/defaultSettings"); exit(1)
       }
     } catch {
       print("FAIL client writes: \(XUIError.safeMessage(error))"); exit(1)
     }
     print("PASS v3 client update mirrors ToClient, enable via bulk, traffic reset, subscription URI (fixture)")
     return
   }
   if expected.hasPrefix("routing-") {
     let model = AppModel(); model.settings = settings
     await model.load()
     guard model.xuiNeedsSettings, model.overview.xui?.error != nil else {
       print("FAIL XUI authentication failures must be classified for Settings navigation")
       exit(1)
     }
     print("PASS XUI authentication failure routes to Settings: \(expected)")
     return
   }
   if expected == "bwh-routing" {
     var bwhSettings = AppSettings()
     bwhSettings.bwhApiBase = "http://127.0.0.1:" + CommandLine.arguments[1] + "/bwh"
     bwhSettings.bwhVeid = "fixture"
     bwhSettings.bwhApiKey = "fixture"
     let model = AppModel(); model.settings = bwhSettings
     await model.load()
     guard model.bwhNeedsSettings, model.overview.bwh?.error != nil else {
       print("FAIL Bandwagon credential failures must be classified for Settings navigation")
       exit(1)
     }
     print("PASS Bandwagon credential failure routes to Settings")
     return
   }
   do {
     let result = try await XUIClient.fetch(settings)
     guard expected == "success", result.clients?.count == 1, result.onlineCount == 1 else { print("FAIL expected \(expected)"); exit(1) }
     print("PASS HTTP cookie+CSRF login, base path, 2FA, authenticated list clients=1 (fixture)")
   } catch {
     let message = XUIError.safeMessage(error)
     guard expected != "success", message.contains(expected) else {
       print("FAIL expected \(expected), received \(message)"); exit(1)
     }
     if expected == "HTTP 200" {
       guard message.contains("fixture rejected") else {
         print("FAIL server authentication message was not preserved: \(message)"); exit(1)
       }
     }
     print("PASS HTTP failure retained: \(expected)")
   }
 }
}
