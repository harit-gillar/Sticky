import AppKit
import XCTest
@testable import Sticky

/// closed → opening → open → closed, and no sticky ever gets two windows.
@MainActor
final class StickyWindowsTests: XCTestCase {
    private var windows: StickyWindows!
    private var made: [NSWindow] = []

    override func setUp() {
        windows = StickyWindows()
    }

    override func tearDown() {
        made.forEach { $0.close() }
        made.removeAll()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        made.append(window)
        return window
    }

    func testStartsClosed() {
        XCTAssertEqual(windows.state(of: UUID()), .closed)
    }

    func testClaimIsOpeningUntilTimeout() {
        let id = UUID()
        windows.claim(id)
        XCTAssertEqual(windows.state(of: id), .opening)
        XCTAssertTrue(windows.isOpen(id: id))

        let later = Date().addingTimeInterval(StickyWindows.openingTimeout + 1)
        XCTAssertEqual(windows.state(of: id, now: later), .closed, "a claim with no window expires")
    }

    func testRegisterOpens() {
        let id = UUID()
        windows.claim(id)
        XCTAssertTrue(windows.register(makeWindow(), for: id))
        XCTAssertEqual(windows.state(of: id), .open)
    }

    func testSecondWindowForSameStickyIsRejected() {
        let id = UUID()
        let first = makeWindow()
        XCTAssertTrue(windows.register(first, for: id))
        XCTAssertFalse(windows.register(makeWindow(), for: id), "duplicate should close itself")
        XCTAssertTrue(windows.register(first, for: id), "the same window can register again")
    }

    func testClosingWindowClosesSticky() {
        let id = UUID()
        let window = makeWindow()
        windows.register(window, for: id)

        window.close()

        XCTAssertEqual(windows.state(of: id), .closed, "cleared synchronously inside close()")
    }

    func testCloseByID() {
        let id = UUID()
        windows.register(makeWindow(), for: id)
        windows.close(id: id)
        XCTAssertEqual(windows.state(of: id), .closed)
    }

    func testRepointedWindowDropsOldSticky() {
        let a = UUID(), b = UUID()
        let window = makeWindow()
        windows.register(window, for: a)
        windows.register(window, for: b)
        XCTAssertEqual(windows.state(of: a), .closed)
        XCTAssertEqual(windows.state(of: b), .open)
    }

    func testCloseAll() {
        let ids = [UUID(), UUID()]
        ids.forEach { windows.register(makeWindow(), for: $0) }
        windows.closeAll()
        XCTAssertTrue(ids.allSatisfy { windows.state(of: $0) == .closed })
    }

    func testShowWithoutOpenerLeavesStickyClosed() {
        // No window has handed over openWindow yet: the request waits instead
        // of pretending the sticky is opening.
        let id = UUID()
        windows.show(id)
        XCTAssertEqual(windows.state(of: id), .closed)
    }
}
