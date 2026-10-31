import SwiftUI

struct SettingsPanelView: View {
    @Binding var sticky: StickyNote
    let colorScheme: ColorScheme
    var onTestConfetti: () -> Void
    var onDuplicateNote: (() -> Void)? = nil
    var onDeleteNote: (() -> Void)? = nil

    @StateObject private var soundManager = SoundManager.shared
    @State private var showCustomColorPicker = false
    @State private var customColor: Color = .yellow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuSection("Theme")
            ForEach(PresetColor.allCases) { preset in
                menuItem(
                    preset.displayName,
                    checked: { if case .preset(let c) = sticky.colorTheme { return c == preset }; return false }()
                ) { sticky.colorTheme = .preset(preset) }
            }
            menuItem("Custom Colour...", checked: { if case .custom = sticky.colorTheme { return true }; return false }()) {
                if case .custom(let hex) = sticky.colorTheme { customColor = Color(hex: hex) }
                else { customColor = sticky.colorTheme.asColor }
                showCustomColorPicker = true
            }

            menuDivider

            menuSection("Sound Effect")
            menuItem("Default", checked: sticky.soundEffect == nil) {
                sticky.soundEffect = nil
            }
            ForEach(SoundEffect.presets) { sound in
                menuItem(sound.displayName, checked: sticky.soundEffect == sound, trailing: {
                    Button(action: { soundManager.previewSound(sound) }) {
                        Image(systemName: "play.circle").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }) {
                    sticky.soundEffect = sound
                    soundManager.previewSound(sound)
                }
            }
            menuItem("📁 Custom...", checked: sticky.soundEffect == .custom) {
                soundManager.importCustomSound()
                if soundManager.selectedSound == .custom {
                    sticky.soundEffect = .custom
                }
            }

            menuDivider

            menuSection("Confetti")
            confettiPickerRow("Style") {
                Picker("", selection: Binding(
                    get: { sticky.confettiStyle ?? ConfettiSettings.shared.style },
                    set: { sticky.confettiStyle = $0 }
                )) {
                    ForEach(ConfettiStyle.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.menu).onChange(of: sticky.confettiStyle) { onTestConfetti() }
            }
            confettiPickerRow("Size") {
                Picker("", selection: Binding(
                    get: { sticky.confettiSize ?? ConfettiSettings.shared.size },
                    set: { sticky.confettiSize = $0 }
                )) {
                    ForEach(ConfettiSize.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).onChange(of: sticky.confettiSize) { onTestConfetti() }
            }
            confettiPickerRow("Amount") {
                Picker("", selection: Binding(
                    get: { sticky.confettiAmount ?? ConfettiSettings.shared.amount },
                    set: { sticky.confettiAmount = $0 }
                )) {
                    ForEach(ConfettiAmount.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).onChange(of: sticky.confettiAmount) { onTestConfetti() }
            }
            confettiPickerRow("Gravity") {
                Picker("", selection: Binding(
                    get: { sticky.confettiGravity ?? ConfettiSettings.shared.gravity },
                    set: { sticky.confettiGravity = $0 }
                )) {
                    ForEach(ConfettiGravity.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).onChange(of: sticky.confettiGravity) { onTestConfetti() }
            }
            confettiPickerRow("Volume") {
                Picker("", selection: Binding(
                    get: { sticky.confettiVolume ?? ConfettiSettings.shared.volume },
                    set: { sticky.confettiVolume = $0 }
                )) {
                    ForEach(ConfettiVolume.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented)
            }
            confettiPickerRow("Colour") {
                Picker("", selection: Binding(
                    get: { sticky.confettiColorScheme ?? ConfettiSettings.shared.colorScheme },
                    set: { sticky.confettiColorScheme = $0 }
                )) {
                    ForEach(ConfettiColorScheme.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.menu).onChange(of: sticky.confettiColorScheme) { onTestConfetti() }
            }
            menuItem("✦  Test Confetti") { onTestConfetti() }

            menuDivider

            menuSection("Options")
            menuItem("Always on Top", checked: sticky.isAlwaysOnTop) {
                sticky.isAlwaysOnTop.toggle()
            }
            menuItem("Sort completed to bottom", checked: sticky.autoSortCompleted) {
                sticky.autoSortCompleted.toggle()
            }
            menuItem("Reset to Defaults") {
                sticky.soundEffect = nil
                sticky.confettiSize = nil
                sticky.confettiAmount = nil
                sticky.confettiGravity = nil
                sticky.confettiVolume = nil
                sticky.confettiColorScheme = nil
                sticky.confettiStyle = nil
            }

            if let onDuplicateNote = onDuplicateNote {
                menuDivider
                menuItem("Duplicate This Note") { onDuplicateNote() }
            }

            if let onDeleteNote = onDeleteNote {
                if onDuplicateNote == nil { menuDivider }
                Button(action: onDeleteNote) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Delete This Note")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        // Grow to the widest row rather than a fixed width: segmented controls
        // got wider in newer macOS, and a fixed frame clipped both edges.
        .frame(minWidth: 360, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .sheet(isPresented: $showCustomColorPicker) { customColorSheet }
    }

    // MARK: - Reusable menu primitives

    private func menuSection(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var menuDivider: some View {
        Divider().padding(.vertical, 4)
    }

    private func menuItem(
        _ label: String,
        checked: Bool = false,
        disabled: Bool = false,
        trailing: (() -> some View)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Checkmark column (fixed width keeps all labels aligned)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(checked ? 1 : 0)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(disabled ? .secondary : .primary)

                Spacer()

                if let trailing = trailing {
                    trailing()
                        .padding(.trailing, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // menuItem overload without trailing view (avoids "some View" ambiguity)
    private func menuItem(
        _ label: String,
        checked: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        menuItem(label, checked: checked, disabled: disabled, trailing: Optional<() -> EmptyView>.none, action: action)
    }

    @ViewBuilder
    private func confettiPickerRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            // Align with menu item text (20px checkmark column + 6px padding)
            Spacer().frame(width: 26)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            content()
            Spacer().frame(width: 6)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var customColorSheet: some View {
        VStack(spacing: 16) {
            Text("Choose Custom Colour").font(.headline)
            ColorPicker("Colour", selection: $customColor, supportsOpacity: false).labelsHidden()
            RoundedRectangle(cornerRadius: 8).fill(customColor)
                .frame(width: 120, height: 60).shadow(radius: 2)
            HStack {
                Button("Cancel") { showCustomColorPicker = false }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    sticky.colorTheme = .custom(customColor.hexString)
                    showCustomColorPicker = false
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 240)
    }
}
