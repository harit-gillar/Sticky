import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: Any?
    private var configuredWindows: Set<ObjectIdentifier> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-warm confetti window and sound so first trigger is instant
        ConfettiWindowController.shared.warmUp()
        _ = SoundManager.shared  // Force singleton init, which pre-loads the sound
        GlobalHotkeyManager.shared.register()


        // Tell any open StickyNoteView to open remaining stickies
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            StickyStore.shared.openAllTrigger += 1
        }

        // Observe new windows to apply sticky styling
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.configureStickyWindow(window)
        }

        // Also catch windows that become visible without becoming key
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.configureStickyWindow(window)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep alive for menu bar
    }

    // MARK: - URL Scheme Handling (e.g. from Raycast)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // AppKit calls this on the main thread; hop to MainActor for Swift isolation
            Task { @MainActor in
                self.handleIncomingURL(url)
            }
        }
    }

    /// sticky://add?stickyID=…&text=…       — append a task
    /// sticky://complete?stickyID=…&taskID=… — tick a task off (never unticks)
    @MainActor
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "sticky" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let items = components?.queryItems else { return }

        var stickyID: UUID?
        var taskID: UUID?
        var text: String?
        for item in items {
            if item.name == "stickyID", let v = item.value { stickyID = UUID(uuidString: v) }
            if item.name == "taskID",   let v = item.value { taskID = UUID(uuidString: v) }
            if item.name == "text",     let v = item.value { text = v }
        }

        guard let id = stickyID,
              var sticky = StickyStore.shared.sticky(for: id) else { return }

        switch url.host {
        case "add":
            guard let t = text,
                  !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            // Add task and persist (this also schedules CloudKit push)
            sticky.addTask(title: t)
            StickyStore.shared.updateSticky(sticky)
            Task { @MainActor in _ = await self.raiseSticky(id: id) }

        case "complete":
            guard let tid = taskID, sticky.completeTask(id: tid) else { return }
            let completed = sticky
            sticky.applyAutoSort()
            StickyStore.shared.updateSticky(sticky)

            // Celebrate once the window is up so confetti lands on it
            Task { @MainActor in
                let frame = await self.raiseSticky(id: id)
                TaskCompletionEffects.play(note: completed, taskID: tid, windowFrame: frame)
            }

        default:
            return
        }
    }

    /// Brings a sticky's window to the front and returns its frame, or nil if
    /// no window turned up.
    @MainActor
    private func raiseSticky(id: UUID) async -> NSRect? {
        NSApp.activate(ignoringOtherApps: true)

        // If a window for this sticky is already open, raise it directly via
        // AppKit. Only fall back to SwiftUI's openWindow when no window exists,
        // since openWindow has been observed to create duplicates for already-
        // open values.
        if StickyWindowRegistry.shared.raiseIfPresent(id: id) {
            return StickyWindowRegistry.shared.frame(for: id)
        }

        // Registry may be empty if the app is cold-launching (openAllTrigger
        // hasn't fired yet). Retry once after a delay; only then fall back to
        // openWindow.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if StickyWindowRegistry.shared.raiseIfPresent(id: id) {
            return StickyWindowRegistry.shared.frame(for: id)
        }
        NotificationCenter.default.post(
            name: .openStickyByID,
            object: nil,
            userInfo: ["stickyID": id, "nonce": UUID()]
        )
        try? await Task.sleep(nanoseconds: 600_000_000)
        return StickyWindowRegistry.shared.frame(for: id)
    }


    private func configureStickyWindow(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)

        // Skip if already configured
        guard !configuredWindows.contains(windowID) else { return }

        // Skip system windows, panels, sheets, menus
        let className = String(describing: type(of: window))
        if className.contains("StatusBar") || className.contains("MenuBar") || className.contains("Panel") {
            return
        }

        // Only configure windows that belong to our "sticky" window group
        // SwiftUI-managed windows for our app
        guard window.styleMask.contains(.titled) else { return }

        configuredWindows.insert(windowID)

        // Apply sticky note styling
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.hasShadow = true

        // Clean up tracking when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let closedWindow = notification.object as? NSWindow else { return }
            self?.configuredWindows.remove(ObjectIdentifier(closedWindow))
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openStickyByID = Notification.Name("OpenStickyByID")
}

/// Ensures only one `.onReceive` handler reacts per posted notification.
/// Multiple `StickyWindowRoot` views are alive when several stickies are open;
/// each receives every notification. We pin acting on it to the first handler
/// that grabs the nonce.
@MainActor
final class URLNotificationDeduper {
    static let shared = URLNotificationDeduper()
    private var processed: Set<UUID> = []

    func shouldProcess(_ nonce: UUID) -> Bool {
        if processed.contains(nonce) { return false }
        processed.insert(nonce)
        // Keep the set bounded; we never need more than the last few
        if processed.count > 64 { processed.removeAll() }
        return true
    }
}

/// Tracks live NSWindow instances by their sticky UUID so AppDelegate can
/// raise an existing window directly instead of asking SwiftUI's openWindow
/// (which has been observed to create duplicates for already-open values).
@MainActor
final class StickyWindowRegistry {
    static let shared = StickyWindowRegistry()

    private final class WeakBox {
        weak var window: NSWindow?
        init(_ w: NSWindow) { self.window = w }
    }

    private var registry: [UUID: WeakBox] = [:]
    /// Ids handed to a window that hasn't registered yet, so two windows
    /// adopting a sticky in the same pass can't pick the same one.
    private var claimed: Set<UUID> = []
    private var closeObservers: [ObjectIdentifier: Any] = [:]

    /// Returns false if another window already shows this sticky; the caller
    /// should close `window` instead of keeping a duplicate.
    @discardableResult
    func register(_ window: NSWindow, for id: UUID) -> Bool {
        if let existing = registry[id]?.window, existing !== window { return false }

        // A window can be re-pointed at another sticky; drop its old entry
        registry = registry.filter { $0.value.window != nil && $0.value.window !== window }
        registry[id] = WeakBox(window)
        claimed.remove(id)

        // Closed windows can outlive close(), so forget them explicitly
        let key = ObjectIdentifier(window)
        guard closeObservers[key] == nil else { return true }
        closeObservers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.registry = self.registry.filter { $0.value.window !== window }
                if let observer = self.closeObservers.removeValue(forKey: key) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
        return true
    }

    func claim(_ id: UUID) {
        claimed.insert(id)
    }

    /// True if a live window for this id is currently open (or about to be).
    func isOpen(id: UUID) -> Bool {
        registry = registry.filter { $0.value.window != nil }
        return registry[id]?.window != nil || claimed.contains(id)
    }

    /// Closes the window showing this sticky, if any.
    func close(id: UUID) {
        registry[id]?.window?.close()
    }

    /// Moves an open window to `frame`. A minimised sticky keeps its current
    /// height and lines its top edge up with the frame's.
    func move(id: UUID, to frame: CGRect, keepHeight: Bool) {
        guard let window = registry[id]?.window else { return }
        var target = frame
        if keepHeight {
            target.size.height = window.frame.height
            target.origin.y = frame.maxY - window.frame.height
        }
        window.setFrame(target, display: true, animate: false)
    }

    /// Screen frame of the live window for this id, if one is open.
    func frame(for id: UUID) -> NSRect? {
        registry[id]?.window?.frame
    }

    /// Returns true if a live window for this id was raised. Cleans up nil
    /// entries as a side-effect.
    func raiseIfPresent(id: UUID) -> Bool {
        registry = registry.filter { $0.value.window != nil }
        guard let window = registry[id]?.window else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

/// Ensures the launch-time "open all stickies" routine runs only once per
/// trigger increment. Multiple StickyNoteViews observe `openAllTrigger`; without
/// this, each one would try to open every other sticky, duplicating windows.
@MainActor
final class OpenAllCoordinator {
    static let shared = OpenAllCoordinator()
    private var lastHandled = 0

    func shouldHandle(_ trigger: Int) -> Bool {
        guard trigger > lastHandled else { return false }
        lastHandled = trigger
        return true
    }
}
