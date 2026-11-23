import XCTest
@testable import Sticky

final class StickyLinkTests: XCTestCase {
    private let stickyID = UUID()

    private func link(_ string: String) -> StickyLink? {
        let filled = string.replacingOccurrences(of: "SID", with: stickyID.uuidString)
        return StickyLink(url: URL(string: filled)!, scheme: "sticky")
    }

    /// "Milk" (open), "Bread" (ticked), "milk" (ticked), "Eggs" (open)
    private func shopping() -> StickyNote {
        var note = StickyNote(id: stickyID, title: "Shopping")
        ["Milk", "Bread", "milk", "Eggs"].forEach { note.addTask(title: $0) }
        note.completeTask(id: note.tasks[1].id)
        note.completeTask(id: note.tasks[2].id)
        return note
    }

    // MARK: - Parsing

    func testParsesEveryCommand() {
        let item = UUID()
        XCTAssertEqual(link("sticky://add?stickyID=SID&text=Milk")?.command, .add(text: "Milk"))
        XCTAssertEqual(link("sticky://complete?stickyID=SID&itemID=\(item)")?.target, .id(item))
        XCTAssertEqual(link("sticky://uncomplete?stickyID=SID&text=Milk")?.command, .uncomplete)
        XCTAssertEqual(link("sticky://delete?stickyID=SID&text=Milk")?.command, .delete)
        XCTAssertEqual(link("sticky://edit?stickyID=SID&text=Milk&newText=Oat%20milk")?.command,
                       .edit(newText: "Oat milk"))
    }

    func testTaskIDStillWorks() {
        let item = UUID()
        XCTAssertEqual(link("sticky://complete?stickyID=SID&taskID=\(item)")?.target, .id(item))
    }

    func testIDWinsOverText() {
        let item = UUID()
        XCTAssertEqual(link("sticky://delete?stickyID=SID&itemID=\(item)&text=Milk")?.target, .id(item))
    }

    func testBadLinksParseToNil() {
        XCTAssertNil(link("other://complete?stickyID=SID&text=Milk"), "wrong scheme")
        XCTAssertNil(link("sticky://explode?stickyID=SID&text=Milk"), "unknown command")
        XCTAssertNil(link("sticky://complete?text=Milk"), "no sticky")
        XCTAssertNil(link("sticky://complete?stickyID=nope&text=Milk"), "bad sticky id")
        XCTAssertNil(link("sticky://complete?stickyID=SID"), "no task")
        XCTAssertNil(link("sticky://complete?stickyID=SID&itemID=nope&text=Milk"), "bad item id")
        XCTAssertNil(link("sticky://complete?stickyID=SID&text=%20%20"), "blank text")
        XCTAssertNil(link("sticky://edit?stickyID=SID&text=Milk"), "edit without newText")
        XCTAssertNil(link("sticky://edit?stickyID=SID&text=Milk&newText="), "edit to nothing")
        XCTAssertNil(link("sticky://add?stickyID=SID"), "add without text")
    }

    func testDevScheme() {
        let url = URL(string: "sticky-dev://delete?stickyID=\(stickyID)&text=Milk")!
        XCTAssertNotNil(StickyLink(url: url, scheme: "sticky-dev"))
        XCTAssertNil(StickyLink(url: url, scheme: "sticky"), "the real app ignores dev links")
    }

    // MARK: - Matching

    func testTextMatchIgnoresCaseAndOuterSpaces() {
        let note = shopping()
        XCTAssertEqual(link("sticky://complete?stickyID=SID&text=%20EGGS%20")?.task(in: note)?.title, "Eggs")
    }

    func testCompleteTakesFirstOpenMatch() {
        let note = shopping()
        let task = link("sticky://complete?stickyID=SID&text=MILK")?.task(in: note)
        XCTAssertEqual(task?.id, note.tasks[0].id, "the open Milk, not the ticked milk")
    }

    func testUncompleteTakesFirstTickedMatch() {
        let note = shopping()
        let task = link("sticky://uncomplete?stickyID=SID&text=milk")?.task(in: note)
        XCTAssertEqual(task?.id, note.tasks[2].id)
    }

    func testDeleteFallsBackToTickedMatch() {
        let note = shopping()
        XCTAssertEqual(link("sticky://delete?stickyID=SID&text=bread")?.task(in: note)?.title, "Bread")
    }

    func testCompleteHasNoTickedFallback() {
        XCTAssertNil(link("sticky://complete?stickyID=SID&text=Bread")?.task(in: shopping()))
    }

    // MARK: - Applying

    func testComplete() throws {
        var note = shopping()
        let change = try XCTUnwrap(link("sticky://complete?stickyID=SID&text=eggs")).apply(to: &note)
        XCTAssertEqual(change, .completed(taskID: note.tasks[3].id))
        XCTAssertTrue(note.tasks[3].isCompleted)
    }

    func testCompleteTwiceDoesNothing() throws {
        var note = shopping()
        let id = note.tasks[1].id // already ticked
        let before = note
        XCTAssertNil(try XCTUnwrap(link("sticky://complete?stickyID=SID&itemID=\(id)")).apply(to: &note))
        XCTAssertEqual(note, before)
    }

    func testUncomplete() throws {
        var note = shopping()
        XCTAssertEqual(try XCTUnwrap(link("sticky://uncomplete?stickyID=SID&text=Bread")).apply(to: &note), .uncompleted)
        XCTAssertFalse(note.tasks[1].isCompleted)
    }

    func testDeleteByID() throws {
        var note = shopping()
        let id = note.tasks[0].id
        XCTAssertEqual(try XCTUnwrap(link("sticky://delete?stickyID=SID&itemID=\(id)")).apply(to: &note), .deleted)
        XCTAssertFalse(note.tasks.contains { $0.id == id })
        XCTAssertEqual(note.tasks.count, 3)
    }

    func testEdit() throws {
        var note = shopping()
        let edit = try XCTUnwrap(link("sticky://edit?stickyID=SID&text=milk&newText=Oat%20milk"))
        XCTAssertEqual(edit.apply(to: &note), .edited)
        XCTAssertEqual(note.tasks[0].title, "Oat milk")
        XCTAssertEqual(note.tasks[2].title, "milk", "only the first open match changes")
    }

    func testNoMatchChangesNothing() throws {
        var note = shopping()
        let before = note
        XCTAssertNil(try XCTUnwrap(link("sticky://delete?stickyID=SID&text=Caviar")).apply(to: &note))
        XCTAssertNil(try XCTUnwrap(link("sticky://delete?stickyID=SID&itemID=\(UUID())")).apply(to: &note))
        XCTAssertEqual(note, before)
    }

    func testAutoSortRespected() throws {
        var note = shopping()
        note.autoSortCompleted = true
        _ = try XCTUnwrap(link("sticky://uncomplete?stickyID=SID&text=bread")).apply(to: &note)
        XCTAssertEqual(note.tasks.map(\.isCompleted), [false, false, false, true], "open tasks first")
    }
}
