import XCTest
@testable import Sticky

final class MinimizeGeometryTests: XCTestCase {
    private let expanded = CGRect(x: 100, y: 200, width: 280, height: 400)

    func testCollapsedHangsFromTopEdge() {
        let strip = MinimizeGeometry.collapsed(expanded)
        XCTAssertEqual(strip.maxY, expanded.maxY)
        XCTAssertEqual(strip.minX, expanded.minX)
        XCTAssertEqual(strip.width, expanded.width)
        XCTAssertEqual(strip.height, MinimizeGeometry.collapsedHeight)
    }

    func testRoundTrip() {
        let strip = MinimizeGeometry.collapsed(expanded)
        XCTAssertEqual(MinimizeGeometry.expanded(fromCollapsed: strip, saved: expanded), expanded)
    }

    func testMovingStripMovesExpandedFrame() {
        var strip = MinimizeGeometry.collapsed(expanded)
        strip.origin.x += 50
        strip.origin.y -= 30
        let moved = MinimizeGeometry.expanded(fromCollapsed: strip, saved: expanded)
        XCTAssertEqual(moved.minX, expanded.minX + 50)
        XCTAssertEqual(moved.maxY, expanded.maxY - 30)
        XCTAssertEqual(moved.height, expanded.height, "keeps the saved height, not the strip's")
    }

    func testResizingStripKeepsSavedHeight() {
        var strip = MinimizeGeometry.collapsed(expanded)
        strip.size.width = 400
        let resized = MinimizeGeometry.expanded(fromCollapsed: strip, saved: expanded)
        XCTAssertEqual(resized.width, 400)
        XCTAssertEqual(resized.height, expanded.height)
    }

    func testNothingSavedUsesDefaultHeight() {
        let strip = CGRect(x: 0, y: 500, width: 280, height: MinimizeGeometry.collapsedHeight)
        let result = MinimizeGeometry.expanded(fromCollapsed: strip, saved: nil)
        XCTAssertEqual(result.height, MinimizeGeometry.defaultExpandedSize.height)
        XCTAssertEqual(result.maxY, strip.maxY)
    }
}

@MainActor
final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isVersion("1.3.1", newerThan: "1.3.0"))
        XCTAssertTrue(Updater.isVersion("1.10.0", newerThan: "1.9.2"))
        XCTAssertTrue(Updater.isVersion("2", newerThan: "1.99"))
        XCTAssertFalse(Updater.isVersion("1.3", newerThan: "1.3.0"))
        XCTAssertFalse(Updater.isVersion("1.2.9", newerThan: "1.3.0"))
    }

    func testMenuTitleFollowsPhase() {
        XCTAssertEqual(Updater.Phase.idle.menuTitle, "Check for Updates…")
        XCTAssertEqual(Updater.Phase.checking.menuTitle, "Checking for Updates…")
        XCTAssertEqual(Updater.Phase.downloading(version: "1.4.0").menuTitle, "Downloading Sticky 1.4.0…")
        XCTAssertEqual(Updater.Phase.installing.menuTitle, "Installing Update…")
    }
}

final class TaskTickingTests: XCTestCase {
    func testCompleteTaskOnlyEverTicks() {
        var note = StickyNote()
        note.addTask(title: "A")
        let id = note.tasks[0].id

        XCTAssertTrue(note.completeTask(id: id))
        XCTAssertTrue(note.tasks[0].isCompleted)
        XCTAssertFalse(note.completeTask(id: id), "already done: no second celebration")
        XCTAssertTrue(note.tasks[0].isCompleted, "never unticks")
        XCTAssertFalse(note.completeTask(id: UUID()), "unknown task")
    }

    func testAutoSortMovesDoneTasksDown() {
        var note = StickyNote()
        note.autoSortCompleted = true
        note.addTask(title: "A")
        note.addTask(title: "B")
        note.completeTask(id: note.tasks[0].id)
        note.applyAutoSort()
        XCTAssertEqual(note.tasks.map(\.title), ["B", "A"])
        XCTAssertEqual(note.tasks.map(\.sortOrder), [0, 1])
    }
}
