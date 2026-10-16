# 3X-UI connection verification

## Result
The native app was rebuilt, ad-hoc signed, installed at `/Users/kun/Desktop/Bandwagon.app`, launched, and its Clients screen verified through macOS Accessibility. It now displays the actual authentication rejection instead of a false empty-client state.

**Production client count remains unknown, not zero.** The configured panel rejects the stored credentials after CSRF validation. No credentials, endpoint host, or client identifiers are recorded here. Settings and server configuration were not changed; stored `XUI_VERIFY_SSL` remains true.

## Live evidence (Swift URLSession, SSL validation enabled)
- GET panel root: HTTP 200, CSRF meta present.
- GET `/csrf-token`: HTTP 200; JSON `obj` is a token string.
- GET `/login`: HTTP 404 (not the login-page GET route).
- POST `/login` without CSRF token: HTTP 403, empty body.
- POST `/login` with same-session CSRF token: HTTP 200, `success:false`.
- Server message: `用户名、密码或双重验证码无效。`
- Both JSON and form login payloads produced the same authentication rejection after CSRF was supplied. Further credential attempts stopped.
- Saved API token and two-factor code are absent. Username and password are present. No values were printed.
- TLS succeeded using the stored settings; no SSL bypass was used or persisted.

Before fix, the real Swift fetch harness returned:
```
configured=true verifySSL=true
FAIL live-fetch domain=XUI code=1 message=3X-UI 登录失败
```
After fix, `bash scripts/test.sh --live` reached the real authentication response and returned exit 1:
```
configured=true verifySSL=true
FAIL live-fetch domain=live.XUIError code=3 message=3X-UI 已拒绝认证（HTTP 200）：请检查用户名、密码或当前双重验证码。
```
This is not a successful live fetch. Valid credentials, a current 2FA code if enabled, or an API token are still required.

## Local regression output
`bash scripts/test.sh` returned exit 0:
```
PASS HTTP cookie+CSRF login, base path, 2FA, authenticated list clients=1 (fixture)
PASS HTTP failure retained: 403
PASS HTTP failure retained: HTTP 200
PASS HTTP failure retained: 无法识别
PASS concurrent refresh publishes XUI before BWH; independent errors/loading
PASS exactly one login per refresh (including concurrent callers)
PASS connection failure surfaces error without false-empty clients
```
The fixture's one client is synthetic test data, not the production count. Tests exercise the real Swift `XUIClient.fetch`, URLSession cookies, authentication, CSRF on online POSTs, parsing, and AppModel. The false-empty test, list-403 test, and online-CSRF test were observed failing before their respective fixes.

## Package verification
- Xcode Swift 6.3.3 with explicit Xcode macOS 26.5 SDK (not CLT SDK).
- `bash scripts/package-app.sh`: release build succeeded.
- `codesign --verify --deep --strict --verbose=2`: valid on disk; satisfies its Designated Requirement.
- Binary: 1,134,064 bytes. `AppIcon.icns` present.
- Installed `__TEXT,__text` and `__TEXT,__cstring` match the built release. Whole-file hash differs because bundle signing changes the signature.
- UI verification output: `PASS packaged app Clients view shows authentication error, not empty state`.
- Screenshot-based window capture could not discover the window; native Accessibility traversal did find it and verified navigation and displayed error without recording private labels.

## Modified production files
- `Sources/Bandwagon/Services/XUIClient.swift`: browser-equivalent form login (`application/x-www-form-urlencoded`), correct cookie-session CSRF, `X-Requested-With`, Origin/Referer, 2FA payload, HTTP errors retained, route fallback restricted to 404/405, session cleanup.
- `Sources/Bandwagon/Services/XUIError.swift` (new): safe HTTP/TLS/authentication messages, preserving the server's non-secret `msg`.
- `Sources/Bandwagon/Services/AppModel.swift`: concurrent independent service loads, coalesced refresh, preserved last successful data, explicit errors rather than fabricated empty arrays.
- `Sources/Bandwagon/Views/ClientsView.swift`: separate loading/unconfigured/error/empty states, no duplicate page refresh.
- `Sources/Bandwagon/Views/OverviewView.swift`, `VPSView.swift`: service errors/loading and no duplicate page refresh.
- `Sources/Bandwagon/Views/SettingsView.swift`: current two-factor code field.
- `scripts/package-app.sh`: matching Xcode toolchain/SDK pinned.

## Added verification files
`Tests/LiveFetch.swift`, `Tests/Probe.swift`, `Tests/StateRegression.swift`, `Tests/HTTPRegression.swift`, `Tests/http_fixture.py`, `Tests/UIVerify.swift`, `scripts/test.sh`.

Only normal login and read-only client/online APIs were used against the configured panel; no server changes, data deletion, SSL-setting changes, or guessed credentials.
