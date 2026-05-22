import Foundation
import SwiftUI

@MainActor
class StickyStore: ObservableObject {
    @Published var stickies: [StickyNote] = []
    var isFirstLaunch: Bool = false
    @Published var openAllTrigger: Int = 0

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private var dirtyIDs: Set<UUID> = []     // stickies queued for CloudKit push

    static let shared = StickyStore()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Sticky", isDirectory: true)

        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }

        self.fileURL = appDir.appendingPathComponent("stickies.json")
        self.stickies = loadFromDisk()

        if stickies.isEmpty {
            createWelcomeNotes()
            saveToDisk()
            isFirstLaunch = true
        }

        // Kick off background CloudKit sync after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await syncFromCloud()
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
                "Add from Alfred — type \"sticky <task>\"",
                "Get the workflows at github.com/Harit556/Sticky",
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
        let format  = StickyFileFormat(stickies: stickies)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(format) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadFromDisk() -> [StickyNote] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let format = try? decoder.decode(StickyFileFormat.self, from: data) else { return [] }
        return format.stickies
    }
}
