import SwiftUI

struct StickyNoteView: View {
    @EnvironmentObject var store: StickyStore
    @Environment(\.colorScheme) var colorScheme

    let stickyID: UUID

    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false
    @State private var stickyWindow: NSWindow?
    @State private var listContentHeight: CGFloat = 0
    @State private var listViewportHeight: CGFloat = 0
    @State private var zoomCoordinator: WindowZoomCoordinator?

    private let minimizedHeight: CGFloat = 36

    private var sticky: Binding<StickyNote> {
        store.binding(for: stickyID)
    }

    var body: some View {
        let note = sticky.wrappedValue

        ZStack {
            note.colorTheme.backgroundColor(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                note.colorTheme.headerColor(for: colorScheme)
                    .frame(height: 2)

                HStack(spacing: 4) {
                    Button(action: toggleMinimize) {
                        Image(systemName: note.isMinimized ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(note.colorTheme.textColor(for: colorScheme).opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)

                    TextField("Title", text: sticky.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(note.colorTheme.textColor(for: colorScheme))
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .padding(.trailing, 14)
                }

                if !note.isMinimized {
                    TodoListView(
                        sticky: sticky,
                        colorScheme: colorScheme,
                        onTaskCompleted: { taskID in handleTaskCompletion(taskID: taskID) },
                        onMetrics: { content, viewport in
                            listContentHeight = content
                            listViewportHeight = viewport
                        }
                    )
                    Spacer(minLength: 0)
                }
            }

            if !note.isMinimized {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PeelShadowView(colorScheme: colorScheme) {
                            createNoteNextToCurrentWindow()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 220, minHeight: note.isMinimized ? minimizedHeight : 180)
        // Right-click anywhere on the sticky opens settings
        .overlay(RightClickHandler { showSettings = true })
        .popover(isPresented: $showSettings, arrowEdge: .trailing) {
            SettingsPanelView(
                sticky: sticky,
                colorScheme: colorScheme,
                onTestConfetti: { fireTestConfetti() },
                onDuplicateNote: { duplicateCurrentNote() },
                onDeleteNote: { deleteCurrentNote() }
            )
        }
        .onChange(of: showSettings) { _, isShowing in
            if isShowing {
                // Elevate the popover window above all stickies
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    for window in NSApplication.shared.windows where window.isVisible {
                        let name = String(describing: type(of: window))
                        if name.contains("Popover") {
                            window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
                        }
                    }
                }
            }
        }
        .onAppear {
            configureWindow()
        }
        .onChange(of: store.openAllTrigger) { _, newValue in
            // Only one observer handles each trigger increment — otherwise every
            // open window would try to open all the others, duplicating windows.
            if OpenAllCoordinator.shared.shouldHandle(newValue) {
                openRemainingStickies()
            }
        }
        .onChange(of: note.isAlwaysOnTop) { _, isOnTop in setWindowLevel(floating: isOnTop) }
        .background(WindowAccessor(window: $stickyWindow) { window in
            // Register this window so AppDelegate can find and raise it when
            // the URL scheme is invoked, instead of calling SwiftUI's openWindow
            // (which has been observed to duplicate already-open windows).
            StickyWindowRegistry.shared.register(window, for: stickyID)
            startTrackingWindowPosition(window)
            setUpZoomButton(window)
        })
    }

    // MARK: - Fit-to-content (green zoom button)

    private func setUpZoomButton(_ window: NSWindow) {
        guard let zoomButton = window.standardWindowButton(.zoomButton) else { return }
        let coord = zoomCoordinator ?? WindowZoomCoordinator()
        coord.onZoom = { fitWindowToContent() }
        zoomButton.target = coord
        zoomButton.action = #selector(WindowZoomCoordinator.handleZoom)
        zoomCoordinator = coord
    }

    private func fitWindowToContent() {
        guard let window = stickyWindow,
              !sticky.wrappedValue.isMinimized,
              listViewportHeight > 0, listContentHeight > 0 else { return }
        // Growing or shrinking by the difference between content and viewport
        // makes the window exactly fit all tasks with no scroll and no slack.
        let delta = listContentHeight - listViewportHeight
        guard abs(delta) > 1 else { return }

        var frame = window.frame
        let maxHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 1200
        let newHeight = min(max(frame.height + delta, 180), maxHeight)
        let appliedDelta = newHeight - frame.height
        frame.origin.y -= appliedDelta // keep the top edge anchored
        frame.size.height = newHeight
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Window Management

    private func configureWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = stickyWindow
                    ?? NSApplication.shared.keyWindow
                    ?? NSApplication.shared.windows.first(where: { $0.isVisible }) else { return }
            let note = sticky.wrappedValue
            window.level = note.isAlwaysOnTop ? .floating : .normal
            if let frame = note.windowFrame {
                if note.isMinimized {
                    let f = CGRect(x: frame.x, y: frame.y + frame.height - minimizedHeight,
                                   width: frame.width, height: minimizedHeight)
                    window.setFrame(f, display: true, animate: false)
                    applyMinimizedConstraints(window)
                } else {
                    window.setFrame(frame.cgRect, display: true, animate: false)
                }
            }
        }
    }

    private func openRemainingStickies() {
        if store.isFirstLaunch { store.isFirstLaunch = false }
        let currentID = stickyID
        let otherStickies = store.stickies.filter { $0.id != currentID }
        for (index, other) in otherStickies.enumerated() {
            let delay = 0.3 + Double(index) * 0.3
            let id = other.id
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Skip stickies that are already open (e.g. restored by macOS),
                // raising them instead. openWindow duplicates already-open values.
                if !StickyWindowRegistry.shared.raiseIfPresent(id: id) {
                    self.openWindow(id: "sticky", value: id)
                }
            }
        }
    }

    private func toggleMinimize() {
        guard let window = stickyWindow else { return }
        let current = window.frame
        if !sticky.wrappedValue.isMinimized {
            // Save current expanded frame, then shrink
            store.updateWindowFrame(for: stickyID, frame: current)
            sticky.wrappedValue.isMinimized = true
            let newFrame = CGRect(x: current.minX, y: current.maxY - minimizedHeight,
                                  width: current.width, height: minimizedHeight)
            window.setFrame(newFrame, display: true, animate: true)
            applyMinimizedConstraints(window)
        } else {
            // Expand back to saved size
            sticky.wrappedValue.isMinimized = false
            let saved = sticky.wrappedValue.windowFrame
            let h = saved?.height ?? 400
            let w = saved?.width ?? 280
            let newFrame = CGRect(x: current.minX, y: current.maxY - h, width: w, height: h)
            window.setFrame(newFrame, display: true, animate: true)
            window.minSize = CGSize(width: 220, height: 180)
            window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    private func applyMinimizedConstraints(_ window: NSWindow) {
        window.minSize = CGSize(width: 220, height: minimizedHeight)
        window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: minimizedHeight)
    }

    private func startTrackingWindowPosition(_ window: NSWindow) {
        // Save position whenever the window stops moving or resizing
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let frame = window?.frame else { return }
            let note = sticky.wrappedValue
            guard !note.isMinimized else { return } // don't overwrite full-size frame while minimised
            store.updateWindowFrame(for: stickyID, frame: frame)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let frame = window?.frame else { return }
            store.updateWindowFrame(for: stickyID, frame: frame)
        }
    }

    private func setWindowLevel(floating: Bool) {
        NSApplication.shared.keyWindow?.level = floating ? .floating : .normal
    }

    private func createNoteNextToCurrentWindow() {
        let currentFrame = NSApplication.shared.keyWindow?.frame
        let note = store.createSticky(nextToFrame: currentFrame)
        openWindow(id: "sticky", value: note.id)
    }

    private func duplicateCurrentNote() {
        showSettings = false
        if let copy = store.duplicateSticky(id: stickyID) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                openWindow(id: "sticky", value: copy.id)
            }
        }
    }

    private func deleteCurrentNote() {
        showSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.keyWindow?.close()
            store.deleteSticky(id: stickyID)
        }
    }

    // MARK: - Actions

    private func fireTestConfetti() {
        let windowFrame = NSApplication.shared.keyWindow?.frame
        let note = sticky.wrappedValue
        DispatchQueue.main.async {
            SoundManager.shared.playCompletionSound(sound: note.soundEffect, volume: note.confettiVolume)
            if let frame = windowFrame {
                ConfettiWindowController.shared.triggerConfetti(
                    atScreenPoint: NSPoint(x: frame.minX + 50, y: frame.maxY - 60),
                    size: note.confettiSize,
                    amount: note.confettiAmount,
                    gravity: note.confettiGravity,
                    colorScheme: note.confettiColorScheme,
                    style: note.confettiStyle
                )
            }
        }
    }

    private func handleTaskCompletion(taskID: UUID) {
        TaskCompletionEffects.play(
            note: sticky.wrappedValue,
            taskID: taskID,
            windowFrame: NSApplication.shared.keyWindow?.frame
        )
    }
}

// MARK: - Task Completion Effects

/// Sound, confetti and Zapier webhook for a ticked task. Shared by the sticky
/// window and the sticky://complete URL (e.g. from Alfred).
@MainActor
enum TaskCompletionEffects {
    static func play(note: StickyNote, taskID: UUID, windowFrame: NSRect?) {
        let task = note.tasks.first(where: { $0.id == taskID })
        let stickyName = note.colorTheme.displayName
        let effectiveAmount = note.confettiAmount ?? ConfettiSettings.shared.amount

        DispatchQueue.main.async {
            SoundManager.shared.playCompletionSound(sound: note.soundEffect, volume: note.confettiVolume)
            if effectiveAmount != .none, let frame = windowFrame {
                ConfettiWindowController.shared.triggerConfetti(
                    atScreenPoint: NSPoint(x: frame.minX + 50, y: frame.maxY - 60),
                    size: note.confettiSize,
                    amount: note.confettiAmount,
                    gravity: note.confettiGravity,
                    colorScheme: note.confettiColorScheme,
                    style: note.confettiStyle
                )
            }
            if let task = task {
                ZapierWebhookService.shared.fireEvent(type: .taskCompleted, stickyID: note.id, stickyName: stickyName, task: task)
            }
        }
    }
}

// MARK: - Window Accessor

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    var onWindow: ((NSWindow) -> Void)? = nil
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let w = view.window {
                self.window = w
                self.onWindow?(w)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Zoom button handler

/// Retains an @objc target so the green zoom button can trigger fit-to-content.
final class WindowZoomCoordinator: NSObject {
    var onZoom: () -> Void = {}
    @objc func handleZoom() { onZoom() }
}
