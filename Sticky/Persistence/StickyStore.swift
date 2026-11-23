import Foundation
import SwiftUI
import os

/// What we found when reading the notes file at launch. "No file yet" and
/// "file we can't read" used to look the same (an empty list), so an
/// unreadable file was silently replaced by the welcome notes.
enum NotesFile {
    case missing
    case loaded([StickyNote])
    case unreadable(Error)
}

/// Set when the notes file couldn't be read: the original was kept at
/// `backupURL` and Sticky started over with the welcome notes.
struct NotesLoadProblem {
    let backupURL: URL?
    let reason: String
}

@MainActor
class StickyStore: ObservableObject {
    @Published var stickies: [StickyNote] = []
    /// Non-nil after launch if the notes file was unreadable. The app shows it once.
    @Published var loadProblem: NotesLoadProblem?

    let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private var dirtyIDs: Set<UUID> = []     // stickies queued for CloudKit push
    /// True only when the notes file was unreadable and couldn't be backed up
    private var savingBlocked = false
    private let log = Logger(subsystem: "com.stickytodos.app", category: "persistence")

    static let shared = StickyStore()

    /// Where notes live. Debug builds use their own folder so they never touch
    /// real notes; `-StickyDataDirectory <path>` overrides both (handy for
    /// tests, agents and trying things out).
    nonisolated static var dataDirectory: URL {
        if let override = UserDefaults.standard.string(forKey: "StickyDataDirectory"), !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
#if DEBUG
        return appSupport.appendingPathComponent("Sticky Dev", isDirectory: true)
#else
        return appSupport.appendingPathComponent("Sticky", isDirectory: true)
#endif
    }

    init(directory: URL = StickyStore.dataDirectory) {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        self.fileURL = directory.appendingPathComponent("stickies.json")
#if os(macOS)
        SandboxMigration.run(to: fileURL)
#endif

        switch Self.readNotes(at: fileURL) {
        case .loaded(let notes) where !notes.isEmpty:
            stickies = notes
            log.info("Loaded \(notes.count, privacy: .public) stickies from \(self.fileURL.path, privacy: .public)")
        case .loaded, .missing:
            log.info("No stickies yet; creating welcome notes")
            createWelcomeNotes()
            saveToDisk()
        case .unreadable(let error):
            // Keep the original before writing anything over it
            let backup = Self.preserveUnreadableFile(at: fileURL)
            loadProblem = NotesLoadProblem(backupURL: backup, reason: error.localizedDescription)
            log.error("Notes file unreadable (\(error.localizedDescription, privacy: .public)); kept a copy at \(backup?.path ?? "nowhere", privacy: .public)")
            createWelcomeNotes()
            if backup != nil {
                saveToDisk()
            } else {
                savingBlocked = true
            }
        }

        // Kick off background CloudKit sync after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await syncFromCloud()
        }
    }

    /// Reads the notes file without side effects, telling "not there" apart
    /// from "there but unreadable".
    nonisolated static func readNotes(at url: URL) -> NotesFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .loaded(try decoder.decode(StickyFileFormat.self, from: data).stickies)
        } catch {
            return .unreadable(error)
        }
    }

    /// Copies an unreadable notes file next to itself with a timestamp, so
    /// nothing is lost when Sticky starts over. Returns nil if the copy failed,
    /// in which case the original must not be overwritten.
    nonisolated static func preserveUnreadableFile(at url: URL) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("stickies.unreadable-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            return backup
        } catch {
            return nil
        }
    }

    // MARK: - Welcome Notes

    private func createWelcomeNotes() {
#if os(macOS)
        let noteWidth  = 280.0
        let noteHeight = 400.0
        let gap        = 12.0
        let screenWidth  = Double(NSScreen.main?.frame.width  ?? 1440)
        let screenHeight = Double(NSScreen.main?.frame.height ?? 900)
        let totalWidth   = noteWidth * 3 + gap * 2
        let startX = (screenWidth  - totalWidth)  / 2
        let startY = (screenHeight - noteHeight) / 2
        func frame(for index: Int) -> CodableRect {
            CodableRect(x: startX + Double(index) * (noteWidth + gap), y: startY, width: noteWidth, height: noteHeight)
        }
#else
        func frame(for index: Int) -> CodableRect { CodableRect() }
#endif

        let welcomeNotes: [(title: String, tasks: [String], theme: StickyColorTheme)] = [
            ("My Tasks", ["You can do it 💪"], .preset(.yellow)),
            ("Shortcuts", [
                "⌘ + Enter — tick a task",
                "Shift + Enter — line break in a task",
                "⌥ + Shift + S — show/hide all stickies",
                "⌘ + N — new sticky",
                "Right click — open settings",
            ], .preset(.green)),
            ("Tips", [
                "Drag the chevron to minimise",
                "Try different confetti styles in Settings",
                "Long tasks? Use Shift+Enter to wrap",
                "Add from Raycast — search \"Sticky\"",
                "Alfred — \"sticky <task>\" to add, \"sticky\" to tick off",
                "Get the workflows at github.com/harit-gillar/Sticky",
            ], .preset(.blue)),
        ]

        for (i, info) in welcomeNotes.enumerated() {
            var note = StickyNote(title: info.title, colorTheme: info.theme, windowFrame: frame(for: i))
            for task in info.tasks { note.addTask(title: task) }
            stickies.append(note)
        }
    }

    // MARK: - CRUD

    @discardableResult
    func createSticky(nextToFrame frame: CGRect? = nil) -> StickyNote {
        var note = StickyNote()
        note.addTask(title: "You can do it 💪")
#if os(macOS)
        if let frame = frame {
            note.windowFrame = CodableRect(
                x: Double(frame.maxX + 12), y: Double(frame.minY),
                width: 280, height: 400
            )
        }
#endif
        stickies.append(note)
        markDirty(note.id)
        scheduleSave()
        return note
    }

    @discardableResult
    func duplicateSticky(id: UUID) -> StickyNote? {
        guard let original = sticky(for: id) else { return nil }
        let copy = StickyNote(
            title: original.title,
            tasks: original.tasks.map { TodoItem(title: $0.title, sortOrder: $0.sortOrder) },
            colorTheme: original.colorTheme,
            windowFrame: original.windowFrame.map {
                CodableRect(x: $0.x + 20, y: $0.y - 20, width: $0.width, height: $0.height)
            },
            isAlwaysOnTop:     original.isAlwaysOnTop,
            autoSortCompleted: original.autoSortCompleted,
            soundEffect:       original.soundEffect,
            confettiSize:      original.confettiSize,
            confettiAmount:    original.confettiAmount,
            confettiGravity:   original.confettiGravity,
            confettiVolume:    original.confettiVolume,
            confettiColorScheme: original.confettiColorScheme,
            confettiStyle:     original.confettiStyle
        )
        stickies.append(copy)
        markDirty(copy.id)
        scheduleSave()
        return copy
    }

    func deleteSticky(id: UUID) {
        stickies.removeAll { $0.id == id }
        dirtyIDs.remove(id)
        Task { await CloudKitSync.shared.delete(id: id) }
        scheduleSave()
    }

    func updateSticky(_ sticky: StickyNote) {
        if let index = stickies.firstIndex(where: { $0.id == sticky.id }) {
            stickies[index] = sticky
            markDirty(sticky.id)
            scheduleSave()
        }
    }

    func sticky(for id: UUID) -> StickyNote? {
        stickies.first { $0.id == id }
    }

    func binding(for id: UUID) -> Binding<StickyNote> {
        Binding(
            get: { [weak self] in self?.stickies.first { $0.id == id } ?? StickyNote(id: id) },
            set: { [weak self] newValue in
                if let index = self?.stickies.firstIndex(where: { $0.id == id }) {
                    self?.stickies[index] = newValue
                    self?.markDirty(id)
                    self?.scheduleSave()
                }
            }
        )
    }

    func resetToFirstLaunch() {
        stickies.removeAll()
        createWelcomeNotes()

        ConfettiSettings.shared.size        = .medium
        ConfettiSettings.shared.amount      = .normal
        ConfettiSettings.shared.gravity     = .medium
        ConfettiSettings.shared.volume      = .medium
        ConfettiSettings.shared.colorScheme = .rainbow

        saveToDisk()
    }

    // MARK: - Window Frame (macOS only)

#if os(macOS)
    func updateWindowFrame(for stickyID: UUID, frame: CGRect) {
        if let index = stickies.firstIndex(where: { $0.id == stickyID }) {
            stickies[index].windowFrame = CodableRect(from: frame)
            markDirty(stickyID)
            scheduleSave()
        }
    }
#endif

    // MARK: - CloudKit Sync

    func syncFromCloud() async {
        do {
            let cloudStickies = try await CloudKitSync.shared.fetchAll()
            mergeFromCloud(cloudStickies)
        } catch {
            print("[StickyStore] syncFromCloud error: \(error)")
        }
    }

    private func mergeFromCloud(_ cloudStickies: [StickyNote]) {
        var changed = false
        for cloudSticky in cloudStickies {
            if let localIndex = stickies.firstIndex(where: { $0.id == cloudSticky.id }) {
                // Keep newer version
                if cloudSticky.lastModifiedAt > stickies[localIndex].lastModifiedAt {
                    stickies[localIndex] = cloudSticky
                    changed = true
                }
            } else {
                // New sticky created on another device — add it
                stickies.append(cloudSticky)
                changed = true
            }
        }
        if changed { saveToDisk() }
    }

    // MARK: - Persistence

    private func markDirty(_ id: UUID) {
        dirtyIDs.insert(id)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            guard !Task.isCancelled else { return }
            saveToDisk()
            saveTask = nil
            await flushDirtyToCloud()
        }
    }

    private func flushDirtyToCloud() async {
        let ids = dirtyIDs
        dirtyIDs.removeAll()
        let toSync = stickies.filter { ids.contains($0.id) }
        for sticky in toSync {
            await CloudKitSync.shared.push(sticky)
        }
    }

    func saveToDisk() {
        // An unreadable file we couldn't back up stays untouched
        guard !savingBlocked else {
            log.error("Not saving: the unreadable notes file couldn't be backed up")
            return
        }
        let format  = StickyFileFormat(stickies: stickies)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(format) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Saving notes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes any change still waiting on the save debounce. Call before quitting,
    /// or an edit made in the last 0.3 s is lost.
    func flushPendingSave() {
        guard let pending = saveTask else { return }
        pending.cancel()
        saveTask = nil
        saveToDisk()
        log.info("Flushed pending save")
    }
}

#if os(macOS)
// MARK: - Sandbox Migration

/// Sticky was sandboxed up to v1.1.x, so its notes and settings lived in
/// ~/Library/Containers/com.stickytodos.app. From v1.2.0 it isn't (so it can
/// update itself), which moves both. On first launch, copy them across.
/// Never deletes the old copies.
enum SandboxMigration {
    private static let container = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.stickytodos.app/Data/Library", isDirectory: true)

    static func run(to notesURL: URL) {
        // Only the real app at its normal location had a sandbox container;
        // dev builds, tests and -StickyDataDirectory runs start clean.
        guard Bundle.main.bundleIdentifier == "com.stickytodos.app",
              UserDefaults.standard.string(forKey: "StickyDataDirectory") == nil else { return }
        let fm = FileManager.default

        let oldNotes = container.appendingPathComponent("Application Support/Sticky/stickies.json")
        if !fm.fileExists(atPath: notesURL.path), fm.fileExists(atPath: oldNotes.path) {
            try? fm.copyItem(at: oldNotes, to: notesURL)
        }

        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        if defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true,
           let oldPrefs = NSDictionary(
               contentsOf: container.appendingPathComponent("Preferences/\(bundleID).plist")
           ) as? [String: Any],
           !oldPrefs.isEmpty {
            defaults.setPersistentDomain(oldPrefs, forName: bundleID)
        }
    }
}
#endif
