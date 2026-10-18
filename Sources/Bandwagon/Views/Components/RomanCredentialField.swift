import AppKit
import SwiftUI

@MainActor
enum RomanInputPolicy {
    static func apply(to field: NSTextField) {
        (field.cell as? NSTextFieldCell)?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
    }
}

/// A native macOS field that keeps credential entry in a Roman input source.
/// This prevents Chinese IME composition from swallowing ASCII characters
/// such as a standalone lowercase "u" in usernames, passwords, and tokens.
struct RomanCredentialField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool

    init(_ placeholder: String, text: Binding<String>, isSecure: Bool = false) {
        self.placeholder = placeholder
        _text = text
        self.isSecure = isSecure
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure
            ? NSSecureTextField(frame: .zero)
            : NSTextField(frame: .zero)

        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        RomanInputPolicy.apply(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        RomanInputPolicy.apply(to: field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RomanCredentialField

        init(_ parent: RomanCredentialField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }
    }
}
