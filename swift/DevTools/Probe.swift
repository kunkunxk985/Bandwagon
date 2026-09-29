import Foundation
@main struct Probe {
 static func main() async {
 let s = SettingsStore.load(); let base = s.xuiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
 let session = URLSession(configuration: .ephemeral)
 var token = ""
 for path in ["/", "/csrf-token", "/login"] {
 do {
 let (d,r) = try await session.data(from: URL(string: base+path)!)
 let h = r as! HTTPURLResponse; let text = String(data:d,encoding:.utf8) ?? ""
 print("GET \(path) status=\(h.statusCode) bytes=\(d.count) csrfMention=\(text.lowercased().contains("csrf"))")
 if let obj = try? JSONSerialization.jsonObject(with:d) as? [String:Any] { token = obj["obj"] as? String ?? ""; print("JSON tokenString=\(!token.isEmpty)") }
 if path == "/csrf-token" {
 for includeToken in [false, true] {
 var req = URLRequest(url: URL(string:base+"/login")!); req.httpMethod = "POST"
 req.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
 if includeToken { req.setValue(token,forHTTPHeaderField:"X-CSRF-Token") }
 let fields = ["username":s.xuiUsername,"password":s.xuiPassword,"twoFactorCode":s.xuiTwoFactor]
 let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
 req.httpBody = fields.sorted(by:{$0.key < $1.key}).map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters:allowed)!)" }.joined(separator:"&").data(using:.utf8)
 let (ld,lr) = try await session.data(for:req)
 let obj = (try? JSONSerialization.jsonObject(with:ld)) as? [String:Any]
 let msg = (obj?["msg"] as? String ?? "").lowercased()
 var safeMsg = msg
 for secret in [s.xuiUsername, s.xuiPassword, s.xuiBaseUrl, s.xuiApiToken, s.xuiTwoFactor] where !secret.isEmpty { safeMsg = safeMsg.replacingOccurrences(of:secret.lowercased(),with:"[redacted]") }
 print("server-message=\(safeMsg)")
 print("POST login csrf=\(includeToken) status=\((lr as! HTTPURLResponse).statusCode) success=\(obj?["success"] as? Bool ?? false) keys=\(obj?.keys.sorted() ?? []) passwordMention=\(msg.contains("password")) factorMention=\(msg.contains("factor")) msgBytes=\(msg.utf8.count)")
 }
 }
 } catch { let e = error as NSError; print("GET \(path) domain=\(e.domain) code=\(e.code)") }
 }
 }
}
