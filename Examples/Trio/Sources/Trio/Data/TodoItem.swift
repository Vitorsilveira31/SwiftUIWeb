struct TodoItem: Identifiable, Hashable {
    let id: Int
    var title: String
    var isDone: Bool = false
}
