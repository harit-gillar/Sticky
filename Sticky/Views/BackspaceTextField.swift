import SwiftUI
import AppKit

/// Custom NSTextField subclass that intercepts CMD+Enter via performKeyEquivalent,
/// which is more reliable than doCommandBy for modifier+key combos.
class TaskTextField: NSTextField {
    var onCmdReturn: (() -> Void)?

    // Keep the wrap width in sync with the actual laid-out width, so the field
    // reports a correct multi-line intrinsic height and SwiftUI gives it room
    // (otherwise long lines clip on a single line).
    override func layout() {
        super.layout()
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // keyCode 36 = Return/Enter
        if event.keyCode == 36,
           let editor = currentEditor(), window?.firstResponder == editor {
            // Shift+Enter: let it fall through to doCommandBy for newline insertion
            if event.modifierFlags.contains(.shift) {
                return false
            }
            if event.modifierFlags.contains(.command) {
                onCmdReturn?()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A TextField that detects backspace on an empty field, Enter key, CMD+Enter, and arrow keys.
struct BackspaceTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "New task..."
    var font: NSFont = .systemFont(ofSize: 13)
    var textColor: NSColor = .labelColor
    var onBackspaceEmpty: () -> Void
    var onSubmit: () -> Void
    var onCmdEnter: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var focusToken: UUID?
    var onFocusGranted: () -> Void

    func makeNSView(context: Context) -> TaskTextField {
        let textField = TaskTextField()
        textField.onCmdReturn = onCmdEnter
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.font = font
        textField.textColor = textColor
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        // Char wrapping so long unbroken tokens (e.g. URLs) wrap instead of
        // clipping off the right edge when the window is narrow.
        textField.lineBreakMode = .byCharWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.maximumNumberOfLines = 0
        textField.usesSingleLineMode = false
        return textField
    }

    func updateNSView(_ textField: TaskTextField, context: Context) {
        context.coordinator.onBackspaceEmpty = onBackspaceEmpty
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onFocusGranted = onFocusGranted
        context.coordinator.textBinding = $text
        textField.onCmdReturn = onCmdEnter

        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.font = font
        textField.textColor = textColor
        textField.placeholderString = placeholder

        let currentToken = focusToken
        if let token = currentToken, token != context.coordinator.lastProcessedFocusToken {
            context.coordinator.lastProcessedFocusToken = token
            DispatchQueue.main.async {
                if let window = textField.window, textField.acceptsFirstResponder {
                    window.makeFirstResponder(textField)
                    onFocusGranted()
                }
            }
        }
        if currentToken == nil {
            context.coordinator.lastProcessedFocusToken = nil
        }
    }

    /// Tell SwiftUI the wrapped height for the proposed width, so the row grows
    /// to fit multi-line / long-URL text instead of clipping it on one line.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TaskTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 1 else { return nil }
        let measured = text.isEmpty ? " " : text
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let attributed = NSAttributedString(
            string: measured,
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let bounding = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: width, height: max(ceil(bounding.height), 18))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            textBinding: $text,
            onBackspaceEmpty: onBackspaceEmpty,
            onSubmit: onSubmit,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onFocusGranted: onFocusGranted
        )
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var textBinding: Binding<String>
        var onBackspaceEmpty: () -> Void
        var onSubmit: () -> Void
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onFocusGranted: () -> Void
        var lastProcessedFocusToken: UUID?

        init(textBinding: Binding<String>,
             onBackspaceEmpty: @escaping () -> Void,
             onSubmit: @escaping () -> Void,
             onMoveUp: @escaping () -> Void,
             onMoveDown: @escaping () -> Void,
             onFocusGranted: @escaping () -> Void) {
            self.textBinding = textBinding
            self.onBackspaceEmpty = onBackspaceEmpty
            self.onSubmit = onSubmit
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onFocusGranted = onFocusGranted
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            textBinding.wrappedValue = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Shift+Enter inserts a line break instead of submitting
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if textView.string.isEmpty {
                    onBackspaceEmpty()
                    return true
                }
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                onMoveUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                onMoveDown()
                return true
            }
            return false
        }

        func controlTextDidBeginEditing(_ obj: Notification) {}
        func controlTextDidEndEditing(_ obj: Notification) {}
    }
}
