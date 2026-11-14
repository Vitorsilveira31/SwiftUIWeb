import Foundation
import SwiftUI
#if !WEB
    import Observation
    import SkipFuse
#endif

@Observable @MainActor final class TaskListViewModel {
    struct State: Equatable {
        var items: [TodoItem] = []
        var draft = ""

        var pendingCount: Int { items.filter { !$0.isDone }.count }
        var canAdd: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    enum Action {
        case load
        case setDraft(String)
        case add
        case toggle(TodoItem.ID)
        case rename(TodoItem.ID, String)
        case delete(TodoItem.ID)
    }

    private(set) var state = State()
    private let repository: any TodoRepository

    init(repository: any TodoRepository) {
        self.repository = repository
        state.items = repository.load()
    }

    func item(_ id: TodoItem.ID) -> TodoItem? {
        state.items.first { $0.id == id }
    }

    func send(_ action: Action) {
        switch action {
        case .load:
            state.items = repository.load()
            return
        case let .setDraft(text):
            state.draft = text
            return
        case .add:
            let title = state.draft.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            let nextID = (state.items.map(\.id).max() ?? 0) + 1
            state.items.append(TodoItem(id: nextID, title: title))
            state.draft = ""
        case let .toggle(id):
            guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
            state.items[index].isDone.toggle()
        case let .rename(id, title):
            guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
            state.items[index].title = title
        case let .delete(id):
            state.items.removeAll { $0.id == id }
        }
        repository.save(state.items)
    }
}
