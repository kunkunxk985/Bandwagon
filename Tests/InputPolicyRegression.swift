import AppKit

@main
struct InputPolicyRegression {
    @MainActor
    static func main() {
        let field = NSSecureTextField(frame: .zero)
        RomanInputPolicy.apply(to: field)
        guard let locales = (field.cell as? NSTextFieldCell)?.allowedInputSourceLocales,
              locales == [NSAllRomanInputSourcesLocaleIdentifier] else {
            print("FAIL credential field does not force Roman input")
            exit(1)
        }
        print("PASS credential fields force Roman input; lowercase u is accepted directly")
    }
}
