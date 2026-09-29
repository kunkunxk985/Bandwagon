import Foundation
@main struct LiveFetch {
    static func main() async {
        let settings = SettingsStore.load()
        print("configured=\(settings.xuiReady) verifySSL=true")
        do {
            let result = try await XUIClient.fetch(settings)
            print("PASS live-fetch clients=\(result.clients?.count ?? 0)")
        } catch {
            let e = error as NSError
            print("FAIL live-fetch domain=\(e.domain) code=\(e.code) message=\(XUIError.safeMessage(error))")
            exit(1)
        }
    }
}
