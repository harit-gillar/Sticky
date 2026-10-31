import SwiftUI

@main
struct StickyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = StickyStore.shared
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        // Main sticky note windows — each one gets a UUID to look up
        WindowGroup(id: "sticky", for: UUID.self) { $stickyID in
            StickyWindowRoot(stickyID: $stickyID)
                .environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: .openStickyByID)) { notif in
                    guard let id = notif.userInfo?["stickyID"] as? UUID,
                          let nonce = notif.userInfo?["nonce"] as? UUID,
                          URLNotificationDeduper.shared.shouldProcess(nonce) else { return }
                    // Raise if already open; only create a window when none exists.
                    if !StickyWindowRegistry.shared.raiseIfPresent(id: id) {
                        openWindow(id: "sticky", value: id)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 280, height: 400)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sticky Note") {
                    let note = store.createSticky()
                    openWindow(id: "sticky", value: note.id)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Notes") {
                ForEach(store.stickies) { sticky in
                    Menu("\(sticky.title) — \(sticky.remainingCount)/\(sticky.totalCount)") {
                        Button("Open") {
                            openWindow(id: "sticky", value: sticky.id)
                        }
                        Button("Delete") {
                            // Close first, or the orphaned window falls back to
                            // showing another sticky
                            StickyWindowRegistry.shared.close(id: sticky.id)
                            store.deleteSticky(id: sticky.id)
                        }
                    }
                }

                Divider()

                Button("New Sticky Note") {
                    let note = store.createSticky()
                    openWindow(id: "sticky", value: note.id)
                }

                Button("Open All Notes") {
                    openAllNotesSideBySide()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Zapier Integration...") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "zapier-settings")
                }
            }

            CommandMenu("Settings") {
                Menu("Sound Effect") {
                    ForEach(SoundEffect.presets) { sound in
                        Button {
                            SoundManager.shared.selectedSound = sound
                            SoundManager.shared.previewSound(sound)
                        } label: {
                            if SoundManager.shared.selectedSound == sound {
                                Text("✓ \(sound.displayName)")
                            } else {
                                Text("   \(sound.displayName)")
                            }
                        }
                    }
                }

                Menu("Confetti Size") {
                    ForEach(ConfettiSize.allCases) { size in
                        Button {
                            ConfettiSettings.shared.size = size
                        } label: {
                            if ConfettiSettings.shared.size == size {
                                Text("✓ \(size.displayName)")
                            } else {
                                Text("   \(size.displayName)")
                            }
                        }
                    }
                }

                Menu("Confetti Amount") {
                    ForEach(ConfettiAmount.allCases) { amount in
                        Button {
                            ConfettiSettings.shared.amount = amount
                        } label: {
                            if ConfettiSettings.shared.amount == amount {
                                Text("✓ \(amount.displayName)")
                            } else {
                                Text("   \(amount.displayName)")
                            }
                        }
                    }
                }

                Menu("Confetti Gravity") {
                    ForEach(ConfettiGravity.allCases) { gravity in
                        Button {
                            ConfettiSettings.shared.gravity = gravity
                        } label: {
                            if ConfettiSettings.shared.gravity == gravity {
                                Text("✓ \(gravity.displayName)")
                            } else {
                                Text("   \(gravity.displayName)")
                            }
                        }
                    }
                }

                Menu("Confetti Volume") {
                    ForEach(ConfettiVolume.allCases) { volume in
                        Button {
                            ConfettiSettings.shared.volume = volume
                        } label: {
                            if ConfettiSettings.shared.volume == volume {
                                Text("✓ \(volume.displayName)")
                            } else {
                                Text("   \(volume.displayName)")
                            }
                        }
                    }
                }

                Menu("Confetti Colour") {
                    ForEach(ConfettiColorScheme.allCases) { scheme in
                        Button {
                            ConfettiSettings.shared.colorScheme = scheme
                        } label: {
                            if ConfettiSettings.shared.colorScheme == scheme {
                                Text("✓ \(scheme.displayName)")
                            } else {
                                Text("   \(scheme.displayName)")
                            }
                        }
                    }
                }

                Menu("Confetti Style") {
                    ForEach(ConfettiStyle.allCases) { s in
                        Button {
                            ConfettiSettings.shared.style = s
                        } label: {
                            if ConfettiSettings.shared.style == s {
                                Text("✓ \(s.displayName)")
                            } else {
                                Text("   \(s.displayName)")
                            }
                        }
                    }
                }

                Divider()

                Button("Zapier Integration...") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "zapier-settings")
                }

                Divider()

                Button("Reset App...") {
                    resetApp()
                }
            }
        }

        // Settings window for Zapier
        Window("Zapier Integration", id: "zapier-settings") {
            ZapierSettingsView()
        }
        .windowResizability(.contentSize)
    }
}

extension StickyApp {
    func resetApp() {
        let alert = NSAlert()
        alert.messageText = "Reset Sticky?"
        alert.informativeText = "This will delete all your sticky notes and settings, returning the app to its first-launch state. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Close all sticky windows (skip internal windows like the confetti overlay)
        for window in NSApplication.shared.windows where window.styleMask.contains(.titled) {
            window.close()
        }

        // Delete all stickies and recreate welcome notes
        store.resetToFirstLaunch()

        // Open the first sticky
        if let first = store.stickies.first {
            openWindow(id: "sticky", value: first.id)
            // Open remaining stickies
            for (index, sticky) in store.stickies.dropFirst().enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.2) {
                    self.openWindow(id: "sticky", value: sticky.id)
                }
            }
        }
    }

    func openAllNotesSideBySide() {
        let noteWidth = 280.0
        let noteHeight = 400.0
        let gap = 12.0
        let screenWidth = Double(NSScreen.main?.frame.width ?? 1440)
        let screenHeight = Double(NSScreen.main?.frame.height ?? 900)
        let totalWidth = noteWidth * Double(store.stickies.count) + gap * Double(max(0, store.stickies.count - 1))
        let startX = max(20, (screenWidth - totalWidth) / 2)
        let startY = (screenHeight - noteHeight) / 2

        for (index, sticky) in store.stickies.enumerated() {
            // Update stored frame so windows line up
            store.updateWindowFrame(
                for: sticky.id,
                frame: CGRect(
                    x: startX + Double(index) * (noteWidth + gap),
                    y: startY,
                    width: noteWidth,
                    height: noteHeight
                )
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.15) {
                // openWindow duplicates already-open values; move those instead
                if StickyWindowRegistry.shared.raiseIfPresent(id: sticky.id) {
                    if let note = store.sticky(for: sticky.id), let frame = note.windowFrame {
                        StickyWindowRegistry.shared.move(
                            id: sticky.id, to: frame.cgRect, keepHeight: note.isMinimized
                        )
                    }
                } else {
                    self.openWindow(id: "sticky", value: sticky.id)
                }
            }
        }
    }
}

// MARK: - Window Root
// Handles the case where SwiftUI opens the window with a nil UUID (first launch)

struct StickyWindowRoot: View {
    @Binding var stickyID: UUID?
    @EnvironmentObject var store: StickyStore

    var body: some View {
        Group {
            if let id = stickyID, store.sticky(for: id) != nil {
                StickyNoteView(stickyID: id)
            } else {
                // First launch, or a window whose sticky is gone (deleted, or
                // restored by macOS from an older session)
                Color.clear.background(WindowAccessor(window: .constant(nil)) { window in
                    adoptStickyOrClose(window)
                })
            }
        }
    }

    /// Shows a sticky that isn't open in another window. If every sticky is
    /// already showing, closes this window rather than duplicating one.
    private func adoptStickyOrClose(_ window: NSWindow) {
        if let id = stickyID, store.sticky(for: id) != nil { return }
        let registry = StickyWindowRegistry.shared

        if let free = store.stickies.first(where: { !registry.isOpen(id: $0.id) }) {
            registry.claim(free.id)
            stickyID = free.id
        } else if store.stickies.isEmpty {
            let note = store.createSticky()
            registry.claim(note.id)
            stickyID = note.id
        } else {
            window.close()
        }
    }
}
