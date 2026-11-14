// The data boundary. A real app swaps this for an API or a database; the view model does not change.
@MainActor protocol TodoRepository {
    func load() -> [TodoItem]
    func save(_ items: [TodoItem])
}

@MainActor final class InMemoryTodoRepository: TodoRepository {
    private var items: [TodoItem] = [
        TodoItem(id: 1, title: "Run on iOS", isDone: true),
        TodoItem(id: 2, title: "Run on Android"),
        TodoItem(id: 3, title: "Run on the Web")
    ]

    func load() -> [TodoItem] { items }
    func save(_ items: [TodoItem]) { self.items = items }
}
