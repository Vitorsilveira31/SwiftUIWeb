import SwiftUI

struct TaskDetailScreen: View {
    let id: TodoItem.ID
    let viewModel: TaskListViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            if let item = viewModel.item(id) {
                TextField(
                    "Title",
                    text: Binding(get: { item.title }, set: { viewModel.send(.rename(id, $0)) })
                )
                Toggle(
                    "Done",
                    isOn: Binding(get: { item.isDone }, set: { _ in viewModel.send(.toggle(id)) })
                )
                Button("Delete task", role: .destructive) {
                    viewModel.send(.delete(id))
                    dismiss()
                }
            } else {
                Text("This task no longer exists.")
            }
        }
        .navigationTitle("Detail")
    }
}
