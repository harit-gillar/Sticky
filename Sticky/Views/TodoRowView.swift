import SwiftUI

struct TodoRowView: View {
    @Binding var task: TodoItem
    let colorTheme: StickyColorTheme
    let colorScheme: ColorScheme
    let onToggle: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onSubmit: () -> Void
    let onCmdEnter: () -> Void
    let onBackspaceEmpty: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let focusToken: UUID?
    let onFocusGranted: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Checkbox
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle(task.id)
                }
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        task.isCompleted
                            ? Color.green.opacity(0.8)
                            : colorTheme.checkboxColor(for: colorScheme)
                    )
            }
            .buttonStyle(.plain)

            // Task text — custom text field that detects backspace on empty
            BackspaceTextField(
                text: $task.title,
                placeholder: "New task...",
                font: .systemFont(ofSize: 13),
                textColor: NSColor(task.isCompleted
                    ? colorTheme.secondaryTextColor(for: colorScheme)
                    : colorTheme.textColor(for: colorScheme)),
                onBackspaceEmpty: {
                    DispatchQueue.main.async {
                        onBackspaceEmpty()
                    }
                },
                onSubmit: onSubmit,
                onCmdEnter: onCmdEnter,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                // Only pass a non-nil token to THIS row when it's the intended focus target.
                // Passing the raw global token to every row caused all rows to fight for focus.
                focusToken: focusToken == task.id ? focusToken : nil,
                onFocusGranted: onFocusGranted
            )
            .frame(maxWidth: .infinity, minHeight: 18)

            // Delete button (visible on hover)
            if isHovering {
                Button(action: {
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.15)) {
                            onDelete(task.id)
                        }
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(colorTheme.secondaryTextColor(for: colorScheme))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Delete task")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
