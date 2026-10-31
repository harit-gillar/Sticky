import Foundation

struct CodableRect: Codable, Hashable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(from rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    init(x: Double = 0, y: Double = 0, width: Double = 280, height: Double = 400) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct StickyNote: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    var title: String
    var tasks: [TodoItem]
    var colorTheme: StickyColorTheme
    var windowFrame: CodableRect?
    var createdAt: Date
    var lastModifiedAt: Date
    var isAlwaysOnTop: Bool
    var autoSortCompleted: Bool
    var isMinimized: Bool

    // Per-sticky sound & confetti settings
    var soundEffect: SoundEffect?
    var confettiSize: ConfettiSize?
    var confettiAmount: ConfettiAmount?
    var confettiGravity: ConfettiGravity?
    var confettiVolume: ConfettiVolume?
    var confettiColorScheme: ConfettiColorScheme?
    var confettiStyle: ConfettiStyle?

    var remainingCount: Int { tasks.filter { !$0.isCompleted }.count }
    var totalCount: Int { tasks.count }

    init(
        id: UUID = UUID(),
        title: String = "My Tasks",
        tasks: [TodoItem] = [],
        colorTheme: StickyColorTheme = .defaultTheme,
        windowFrame: CodableRect? = nil,
        createdAt: Date = Date(),
        lastModifiedAt: Date = Date(),
        isAlwaysOnTop: Bool = true,
        autoSortCompleted: Bool = false,
        isMinimized: Bool = false,
        soundEffect: SoundEffect? = nil,
        confettiSize: ConfettiSize? = nil,
        confettiAmount: ConfettiAmount? = nil,
        confettiGravity: ConfettiGravity? = nil,
        confettiVolume: ConfettiVolume? = nil,
        confettiColorScheme: ConfettiColorScheme? = nil,
        confettiStyle: ConfettiStyle? = nil
    ) {
        self.id = id
        self.title = title
        self.tasks = tasks
        self.colorTheme = colorTheme
        self.windowFrame = windowFrame
        self.createdAt = createdAt
        self.lastModifiedAt = lastModifiedAt
        self.isAlwaysOnTop = isAlwaysOnTop
        self.autoSortCompleted = autoSortCompleted
        self.isMinimized = isMinimized
        self.soundEffect = soundEffect
        self.confettiSize = confettiSize
        self.confettiAmount = confettiAmount
        self.confettiGravity = confettiGravity
        self.confettiVolume = confettiVolume
        self.confettiColorScheme = confettiColorScheme
        self.confettiStyle = confettiStyle
    }

    mutating func addTask(title: String = "") {
        let sortOrder = (tasks.map(\.sortOrder).max() ?? -1) + 1
        let task = TodoItem(title: title, sortOrder: sortOrder)
        tasks.append(task)
        lastModifiedAt = Date()
    }

    mutating func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        lastModifiedAt = Date()
    }

    mutating func toggleTask(id: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].isCompleted.toggle()
            lastModifiedAt = Date()
        }
    }

    /// Ticks a task without ever unticking it. Returns false if the task is
    /// missing or already done, so callers can skip the celebration.
    @discardableResult
    mutating func completeTask(id: UUID) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              !tasks[index].isCompleted else { return false }
        tasks[index].isCompleted = true
        lastModifiedAt = Date()
        return true
    }

    /// When auto-sort is on: incomplete tasks first, completed tasks last
    mutating func applyAutoSort() {
        guard autoSortCompleted else { return }
        let incomplete = tasks.filter { !$0.isCompleted }
        let completed = tasks.filter { $0.isCompleted }
        tasks = incomplete + completed
        for i in tasks.indices {
            tasks[i].sortOrder = i
        }
    }

    mutating func updateTaskTitle(id: UUID, title: String) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].title = title
            lastModifiedAt = Date()
        }
    }

    mutating func moveTask(from source: IndexSet, to destination: Int) {
        tasks.move(fromOffsets: source, toOffset: destination)
        for i in tasks.indices {
            tasks[i].sortOrder = i
        }
        lastModifiedAt = Date()
    }
}

struct StickyFileFormat: Codable {
    var schemaVersion: Int = 1
    var stickies: [StickyNote]
}
