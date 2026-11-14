import SwiftUI

struct TaskListScreen: View {
    let viewModel: TaskListViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    TextField(
                        "New task",
                        text: Binding(get: { viewModel.state.draft }, set: { viewModel.send(.setDraft($0)) })
                    )
                    .onSubmit { viewModel.send(.add) }
                    .accessibilityIdentifier("task-draft")
                    Button("Add") { viewModel.send(.add) }
                        .disabled(!viewModel.state.canAdd)
                        .accessibilityIdentifier("task-add")
                }
            }

            Section("\(viewModel.state.pendingCount) pending") {
                ForEach(viewModel.state.items) { item in
                    NavigationLink(value: item.id) {
                        TaskRow(item: item) { viewModel.send(.toggle(item.id)) }
                    }
                }
            }
        }
        .navigationTitle("Tasks")
        .navigationDestination(for: Int.self) { id in
            TaskDetailScreen(id: id, viewModel: viewModel)
        }
    }
}

struct TaskRow: View {
    let item: TodoItem
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            Text(item.title)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
        }
    }
}
