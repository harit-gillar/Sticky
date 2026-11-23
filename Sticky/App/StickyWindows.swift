import AppKit
import SwiftUI
import os

/// The one place that knows which sticky has a window. Each sticky is in one
/// of three states:
///
///     closed ──show / claim──▶ opening ──window registers──▶ open
///        ▲                        │                            │
///        └──── no window in 5 s ──┘◀──────── window closes ────┘
///
/// Everything that wants a sticky on screen calls `show(_:)`: launch, the
/// Notes menu, New Sticky, Open All, Reset and sticky:// links. SwiftUI's
/// openWindow duplicates values that are already open, so it's only ever
/// called from here, for a sticky that is `closed`.
///
/// Transitions are logged: `log stream --predicate 'subsystem == "com.stickytodos.app"'`.
@MainActor
final class StickyWindows {
    static let shared = StickyWindows()

    enum State: Equatable {
        case closed
        case opening
        case open
    }

    /// How long an `opening` sticky waits for its window before counting as closed again
    static let openingTimeout: TimeInterval = 5

    private final class WeakBox {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    private enum Slot {
        case opening(since: Date)
        case open(WeakBox)
    }

    private var slots: [UUID: Slot] = [:]
    private var closeObservers: [ObjectIdentifier: Any] = [:]
    /// show() calls that arrived before any window could hand us openWindow
    private var queued: [UUID] = []
    private let log = Logger(subsystem: "com.stickytodos.app", category: "windows")

    /// SwiftUI's openWindow, captured from the first sticky window to appear.
    /// Only views can get it, but sticky:// links arrive at AppDelegate,
    /// possibly with every window closed.
    var opener: OpenWindowAction? {
        didSet {
            guard opener != nil, !queued.isEmpty else { return }
            let pending = queued
            queued.removeAll()
            pending.forEach(show)
        }
    }

    // MARK: - State

    func state(of id: UUID, now: Date = Date()) -> State {
        switch slots[id] {
        case .open(let box)? where box.window != nil:
            return .open
        case .opening(let since)? where now.timeIntervalSince(since) < Self.openingTimeout:
            return .opening
        default:
            return .closed
        }
    }

    /// True if the sticky has a window, or one is on its way.
    func isOpen(id: UUID) -> Bool {
        state(of: id) != .closed
    }

    // MARK: - Transitions

    /// Puts a sticky on screen: raises its window, or opens one if it has none.
    func show(_ id: UUID) {
        switch state(of: id) {
        case .open:
            _ = raise(id)
        case .opening:
            log.debug("show \(id, privacy: .public): already opening")
        case .closed:
            guard let opener else {
                log.info("show \(id, privacy: .public): queued until a window can open it")
                if !queued.contains(id) { queued.append(id) }
                return
            }
            transition(id, to: .opening(since: Date()))
            opener(id: "sticky", value: id)
        }
    }

    /// Shows several stickies, a beat apart so SwiftUI isn't asked to open a
    /// pile of windows in one go.
    func showAll(_ ids: [UUID], stagger: TimeInterval = 0.3) {
        for (index, id) in ids.enumerated() {
            if index == 0 {
                show(id)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + stagger * Double(index)) { [weak self] in
                    self?.show(id)
                }
            }
        }
    }

    /// Marks a sticky as on its way to a window that already exists (an empty
    /// window adopting it), so another window can't adopt the same one.
    func claim(_ id: UUID) {
        transition(id, to: .opening(since: Date()))
    }

    /// Called by a sticky's window once it's on screen. Returns false if a
    /// different window already shows this sticky: the caller should close
    /// `window` rather than keep a duplicate.
    @discardableResult
    func register(_ window: NSWindow, for id: UUID) -> Bool {
        if case .open(let box)? = slots[id], let existing = box.window, existing !== window {
            log.notice("window \(window.windowNumber, privacy: .public) is a duplicate of \(id, privacy: .public); closing it")
            return false
        }

        // A window can be re-pointed at another sticky; drop its old slot
        for (otherID, slot) in slots where otherID != id {
            if case .open(let box) = slot, box.window === window { slots[otherID] = nil }
        }
        transition(id, to: .open(WeakBox(window)))
        observeClose(of: window)
        return true
    }

    /// Closes the window showing this sticky, if any. The sticky is `closed`
    /// as soon as this returns.
    func close(id: UUID) {
        let window = window(for: id)
        transition(id, to: nil)
        window?.close()
    }

    /// Closes every sticky window (Reset App). Everything is `closed` after.
    func closeAll() {
        for id in Array(slots.keys) { close(id: id) }
        queued.removeAll()
    }

    // MARK: - Windows

    /// Brings an open sticky's window to the front. Returns false if it has none.
    func raise(_ id: UUID) -> Bool {
        guard let window = window(for: id) else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Screen frame of the sticky's window if it's actually showing: not
    /// hidden with ⌥⇧S or minimised to the Dock.
    func visibleFrame(for id: UUID) -> NSRect? {
        guard let window = window(for: id), window.isVisible, !window.isMiniaturized else { return nil }
        return window.frame
    }

    /// Moves an open window to `frame`. A minimised sticky keeps its current
    /// height and lines its top edge up with the frame's.
    func move(id: UUID, to frame: CGRect, keepHeight: Bool) {
        guard let window = window(for: id) else { return }
        var target = frame
        if keepHeight {
            target.size.height = window.frame.height
            target.origin.y = frame.maxY - window.frame.height
        }
        window.setFrame(target, display: true, animate: false)
    }

    private func window(for id: UUID) -> NSWindow? {
        if case .open(let box)? = slots[id] { return box.window }
        return nil
    }

    // MARK: - Internals

    private func transition(_ id: UUID, to slot: Slot?) {
        let before = state(of: id)
        slots[id] = slot
        let after = state(of: id)
        if before != after {
            log.info("\(id, privacy: .public): \(String(describing: before), privacy: .public) → \(String(describing: after), privacy: .public)")
        }
    }

    /// Closed windows can outlive close(), so forget them as soon as they close.
    /// `queue: nil` runs this synchronously inside close(), so nothing can see
    /// (and re-raise) a window that's on its way out.
    private func observeClose(of window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard closeObservers[key] == nil else { return }
        closeObservers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for (id, slot) in self.slots {
                    if case .open(let box) = slot, box.window === window { self.transition(id, to: nil) }
                }
                if let observer = self.closeObservers.removeValue(forKey: key) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
}
