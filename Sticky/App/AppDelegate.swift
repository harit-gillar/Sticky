import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: Any?
    private var configuredWindows: Set<ObjectIdentifier> = []

    /// True while the app is only hosting unit tests: skip launch side effects
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        // Pre-warm confetti window and sound so first trigger is instant
        ConfettiWindowController.shared.warmUp()
        _ = SoundManager.shared  // Force singleton init, which pre-loads the sound
        GlobalHotkeyManager.shared.register()

        // SwiftUI opens (or restores) the first window itself; once it's up,
        // open every other sticky. show() skips the ones already open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            StickyWindows.shared.showAll(StickyStore.shared.stickies.map(\.id))
        }

        // If the notes file couldn't be read, say so once, after the stickies are up
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let problem = StickyStore.shared.loadProblem {
                Self.showLoadProblem(problem)
                StickyStore.shared.loadProblem = nil
            }
        }

        // Once the stickies are up, quietly look for a new version (daily)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Updater.shared.checkInBackgroundIfDue()
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

    func applicationWillTerminate(_ notification: Notification) {
        // Don't lose an edit still waiting on the save debounce
        MainActor.assumeIsolated { StickyStore.shared.flushPendingSave() }
    }

    @MainActor
    private static func showLoadProblem(_ problem: NotesLoadProblem) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Sticky couldn't read your notes"
        if let backup = problem.backupURL {
            alert.informativeText = "The file was kept as \(backup.lastPathComponent), and Sticky has started with fresh notes.\n\n\(problem.reason)"
            alert.addButton(withTitle: "Show in Finder")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([backup])
            }
        } else {
            alert.informativeText = "Sticky couldn't make a copy of the file either, so it won't save over it. Quit Sticky and move stickies.json somewhere safe.\n\n\(problem.reason)"
            alert.runModal()
        }
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

    /// The app's link scheme: `sticky`, or `sticky-dev` for Debug builds so a
    /// dev copy never answers links meant for the real app.
    static let urlScheme: String = {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first ?? "sticky"
    }()

    /// Handles sticky:// links (see StickyLink for the commands). Every change
    /// goes through StickyStore, so it saves and syncs like a click. Only
    /// `add` brings Sticky forward; the rest work quietly in the background.
    /// Bad links are ignored.
    @MainActor
    private func handleIncomingURL(_ url: URL) {
        guard let link = StickyLink(url: url, scheme: Self.urlScheme),
              var sticky = StickyStore.shared.sticky(for: link.stickyID) else { return }
        guard let change = link.apply(to: &sticky) else { return }
        StickyStore.shared.updateSticky(sticky)

        switch change {
        case .added:
            NSApp.activate(ignoringOtherApps: true)
            StickyWindows.shared.show(link.stickyID)
        case .completed(let taskID):
            // Sound and Zapier like a click; confetti only if the sticky is on screen
            TaskCompletionEffects.play(
                note: sticky,
                taskID: taskID,
                windowFrame: StickyWindows.shared.visibleFrame(for: link.stickyID)
            )
        case .uncompleted, .deleted, .edited:
            break
        }
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
