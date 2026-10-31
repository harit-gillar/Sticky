import SwiftUI

struct TodoListView: View {
    @Binding var sticky: StickyNote
    let colorScheme: ColorScheme
    let onTaskCompleted: (UUID) -> Void
    /// Reports (full content height, visible viewport height) so the parent can
    /// fit-to-content resize the window.
    var onMetrics: ((CGFloat, CGFloat) -> Void)? = nil

    @State private var focusToken: UUID?
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    private var fadeColor: Color {
        sticky.colorTheme.backgroundColor(for: colorScheme)
    }

    var body: some View {
        GeometryReader { outer in
            let viewport = outer.size.height
            let canScrollUp = scrollOffset > 4
            let canScrollDown = contentHeight - scrollOffset - viewport > 4

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($sticky.tasks) { $task in
                            TodoRowView(
                                task: $task,
                                colorTheme: sticky.colorTheme,
                                colorScheme: colorScheme,
                                onToggle: { taskID in
                                    toggleTask(taskID)
                                },
                                onDelete: { taskID in
                                    deleteAndFocusPrevious(taskID, proxy: proxy)
                                },
                                onSubmit: {
                                    addNewTaskAfter(task.id, proxy: proxy)
                                },
                                onCmdEnter: {
                                    toggleTask(task.id)
                                },
                                onBackspaceEmpty: {
                                    deleteAndFocusPrevious(task.id, proxy: proxy)
                                },
                                onMoveUp: {
                                    focusPreviousTask(from: task.id, proxy: proxy)
                                },
                                onMoveDown: {
                                    focusNextTask(from: task.id, proxy: proxy)
                                },
                                focusToken: focusToken,
                                onFocusGranted: {
                                    // Clear the token so it doesn't re-fire on every SwiftUI update
                                    focusToken = nil
                                }
                            )
                            .id(task.id)
                        }
                    }
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(
                                key: ScrollMetricsKey.self,
                                value: ScrollMetrics(
                                    contentHeight: inner.size.height,
                                    offset: -inner.frame(in: .named("stickyScroll")).minY
                                )
                            )
                        }
                    )
                }
                .coordinateSpace(name: "stickyScroll")
                .onPreferenceChange(ScrollMetricsKey.self) { metrics in
                    contentHeight = metrics.contentHeight
                    scrollOffset = metrics.offset
                    onMetrics?(metrics.contentHeight, viewport)
                }
                .onChange(of: viewport) { _, h in
                    onMetrics?(contentHeight, h)
                }
            }
            // Fade hints: signal there's more content above / below the fold.
            .overlay(alignment: .top) {
                LinearGradient(colors: [fadeColor, fadeColor.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)
                    .allowsHitTesting(false)
                    .opacity(canScrollUp ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: canScrollUp)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [fadeColor.opacity(0), fadeColor],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                    .allowsHitTesting(false)
                    .opacity(canScrollDown ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: canScrollDown)
            }
        }
    }

    // MARK: - Toggle

    private func toggleTask(_ taskID: UUID) {
        let wasCompleted = sticky.tasks.first(where: { $0.id == taskID })?.isCompleted ?? false
        sticky.toggleTask(id: taskID)
        if !wasCompleted {
            onTaskCompleted(taskID)
        }
        sticky.applyAutoSort()
    }

    // MARK: - Arrow Key Navigation

    private func focusPreviousTask(from currentID: UUID, proxy: ScrollViewProxy) {
        guard let index = sticky.tasks.firstIndex(where: { $0.id == currentID }) else { return }
        guard index > 0 else { return }
        let targetID = sticky.tasks[index - 1].id
        requestFocus(targetID, proxy: proxy, anchor: .center)
    }

    private func focusNextTask(from currentID: UUID, proxy: ScrollViewProxy) {
        guard let index = sticky.tasks.firstIndex(where: { $0.id == currentID }) else { return }
        guard index < sticky.tasks.count - 1 else { return }
        let targetID = sticky.tasks[index + 1].id
        requestFocus(targetID, proxy: proxy, anchor: .center)
    }

    // MARK: - Task Management

    private func addNewTaskAfter(_ afterID: UUID, proxy: ScrollViewProxy) {
        guard let index = sticky.tasks.firstIndex(where: { $0.id == afterID }) else { return }
        let sortOrder = sticky.tasks[index].sortOrder + 1
        for i in sticky.tasks.indices where sticky.tasks[i].sortOrder >= sortOrder {
            sticky.tasks[i].sortOrder += 1
        }
        let newTask = TodoItem(sortOrder: sortOrder)
        sticky.tasks.insert(newTask, at: index + 1)
        sticky.lastModifiedAt = Date()

        requestFocus(newTask.id, proxy: proxy, anchor: .center)
    }

    private func deleteAndFocusPrevious(_ taskID: UUID, proxy: ScrollViewProxy) {
        guard let index = sticky.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        // Don't delete the very last task
        guard sticky.tasks.count > 1 else { return }

        // Find the task to focus after deletion (previous, or next if first)
        let focusID: UUID?
        if index > 0 {
            focusID = sticky.tasks[index - 1].id
        } else {
            focusID = sticky.tasks[1].id
        }

        // First focus the target, then delete after a beat
        if let id = focusID {
            requestFocus(id, proxy: proxy, anchor: .center)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.15)) {
                sticky.deleteTask(id: taskID)
            }
            if let id = focusID {
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func requestFocus(_ taskID: UUID, proxy: ScrollViewProxy, anchor: UnitPoint) {
        // Clear first so if the same ID is requested again, it registers as a new token
        focusToken = nil
        DispatchQueue.main.async {
            focusToken = taskID
            withAnimation(.easeOut(duration: 0.1)) {
                proxy.scrollTo(taskID, anchor: anchor)
            }
        }
    }
}

// MARK: - Scroll metrics

private struct ScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var offset: CGFloat = 0
}

private struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue = ScrollMetrics()
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        value = nextValue()
    }
}
