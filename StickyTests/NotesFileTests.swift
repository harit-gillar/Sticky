import XCTest
@testable import Sticky

/// The notes file at launch is missing, loaded or unreadable, and an
/// unreadable file must never be lost.
@MainActor
final class NotesFileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var notesURL: URL { dir.appendingPathComponent("stickies.json") }

    private func writeNotes(_ notes: [StickyNote]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(StickyFileFormat(stickies: notes)).write(to: notesURL)
    }

    func testMissingFile() {
        guard case .missing = StickyStore.readNotes(at: notesURL) else {
            return XCTFail("expected .missing")
        }
    }

    func testLoadedFile() throws {
        var note = StickyNote(title: "Groceries")
        note.addTask(title: "Milk")
        try writeNotes([note])

        guard case .loaded(let notes) = StickyStore.readNotes(at: notesURL) else {
            return XCTFail("expected .loaded")
        }
        XCTAssertEqual(notes.map(\.title), ["Groceries"])
        XCTAssertEqual(notes.first?.tasks.map(\.title), ["Milk"])
    }

    func testUnreadableFile() throws {
        try Data("{ not json".utf8).write(to: notesURL)
        guard case .unreadable = StickyStore.readNotes(at: notesURL) else {
            return XCTFail("expected .unreadable")
        }
    }

    func testStoreKeepsUnreadableFileAndStartsFresh() throws {
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: notesURL)

        let store = StickyStore(directory: dir)

        let problem = try XCTUnwrap(store.loadProblem)
        let backup = try XCTUnwrap(problem.backupURL)
        XCTAssertEqual(try Data(contentsOf: backup), garbage, "original bytes kept")
        XCTAssertFalse(store.stickies.isEmpty, "started with the welcome notes")
        guard case .loaded = StickyStore.readNotes(at: notesURL) else {
            return XCTFail("fresh notes saved in place of the unreadable file")
        }
    }

    func testMissingFileStartsWithWelcomeNotes() {
        let store = StickyStore(directory: dir)
        XCTAssertNil(store.loadProblem)
        XCTAssertEqual(store.stickies.count, 3)
        guard case .loaded(let saved) = StickyStore.readNotes(at: notesURL) else {
            return XCTFail("welcome notes saved")
        }
        XCTAssertEqual(saved.count, 3)
    }

    func testFlushPendingSaveWritesImmediately() throws {
        let store = StickyStore(directory: dir)
        var first = try XCTUnwrap(store.stickies.first)
        first.title = "Renamed"
        store.updateSticky(first) // schedules a debounced save

        store.flushPendingSave()

        guard case .loaded(let saved) = StickyStore.readNotes(at: notesURL) else {
            return XCTFail("expected saved notes")
        }
        XCTAssertEqual(saved.first?.title, "Renamed")
    }
}
