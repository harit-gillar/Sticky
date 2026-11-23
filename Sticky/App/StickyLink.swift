import Foundation

/// A parsed sticky:// command. Parsing and applying are pure, so they're unit
/// tested; AppDelegate saves the result through StickyStore, exactly like a
/// click in the window would.
///
///     sticky://add?stickyID=…&text=…
///     sticky://complete?stickyID=…&itemID=…        (or &text=…)
///     sticky://uncomplete?stickyID=…&itemID=…      (or &text=…)
///     sticky://delete?stickyID=…&itemID=…          (or &text=…)
///     sticky://edit?stickyID=…&itemID=…&newText=…  (or &text=…&newText=…)
///
/// Anything malformed parses to nil and is ignored.
struct StickyLink: Equatable {
    enum Command: Equatable {
        case add(text: String)
        case complete
        case uncomplete
        case delete
        case edit(newText: String)
    }

    /// Which task a command acts on
    enum Target: Equatable {
        case id(UUID)
        case text(String)
    }

    let stickyID: UUID
    let command: Command
    /// nil only for `add`
    let target: Target?

    init?(url: URL, scheme: String) {
        guard url.scheme?.lowercased() == scheme.lowercased(),
              let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] where params[item.name] == nil {
            params[item.name] = item.value ?? ""
        }

        guard let stickyID = params["stickyID"].flatMap(UUID.init(uuidString:)) else { return nil }
        self.stickyID = stickyID

        func nonEmpty(_ key: String) -> String? {
            guard let value = params[key],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }

        if host == "add" {
            guard let text = nonEmpty("text") else { return nil }
            command = .add(text: text)
            target = nil
            return
        }

        // itemID (or taskID, what Sticky 1.3 used) wins over text. An ID
        // that's there but isn't a UUID is a bad link, not a cue to use text.
        if let rawID = params["itemID"] ?? params["taskID"] {
            guard let id = UUID(uuidString: rawID) else { return nil }
            target = .id(id)
        } else if let text = nonEmpty("text") {
            target = .text(text)
        } else {
            return nil
        }

        switch host {
        case "complete":   command = .complete
        case "uncomplete": command = .uncomplete
        case "delete":     command = .delete
        case "edit":
            guard let newText = nonEmpty("newText") else { return nil }
            command = .edit(newText: newText)
        default:
            return nil
        }
    }

    /// The task this link points at, or nil if none matches.
    ///
    /// Text matches ignore case and spaces at either end. `complete`, `delete`
    /// and `edit` take the first open match; `delete` and `edit` fall back to
    /// the first ticked match so ticked tasks can be removed by name too.
    /// `uncomplete` takes the first ticked match.
    func task(in note: StickyNote) -> TodoItem? {
        switch target {
        case .id(let id)?:
            return note.tasks.first { $0.id == id }
        case .text(let text)?:
            let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = note.tasks.filter {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(wanted) == .orderedSame
            }
            let open = matches.first { !$0.isCompleted }
            let ticked = matches.first { $0.isCompleted }
            switch command {
            case .complete:         return open
            case .uncomplete:       return ticked
            case .delete, .edit:    return open ?? ticked
            case .add:              return nil
            }
        case nil:
            return nil
        }
    }

    /// What applying a link changed
    enum Change: Equatable {
        case added
        case completed(taskID: UUID)
        case uncompleted
        case deleted
        case edited
    }

    /// Applies the link to `note`. Returns nil, leaving `note` untouched, when
    /// there's nothing to do (no matching task, already ticked, same text…).
    func apply(to note: inout StickyNote) -> Change? {
        if case .add(let text) = command {
            note.addTask(title: text)
            return .added
        }
        guard let task = task(in: note) else { return nil }

        switch command {
        case .add:
            return nil
        case .complete:
            guard note.completeTask(id: task.id) else { return nil }
            note.applyAutoSort()
            return .completed(taskID: task.id)
        case .uncomplete:
            guard note.uncompleteTask(id: task.id) else { return nil }
            note.applyAutoSort()
            return .uncompleted
        case .delete:
            note.deleteTask(id: task.id)
            return .deleted
        case .edit(let newText):
            guard task.title != newText else { return nil }
            note.updateTaskTitle(id: task.id, title: newText)
            return .edited
        }
    }
}
