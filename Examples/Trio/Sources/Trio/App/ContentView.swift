import SwiftUI

enum AppTab: String, Hashable {
    case counter, tasks, about
}

struct ContentView: View {
    @AppStorage("trio.tab") var tab = AppTab.counter
    @AppStorage("trio.darkMode") var darkMode = false
    @State var tasks = TaskListViewModel(repository: InMemoryTodoRepository())

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                CounterScreen()
            }
            .tabItem { Label("Counter", systemImage: "plus") }
            .tag(AppTab.counter)

            NavigationStack {
                TaskListScreen(viewModel: tasks)
            }
            .tabItem { Label("Tasks", systemImage: "list.bullet") }
            .tag(AppTab.tasks)

            NavigationStack {
                AboutScreen(darkMode: $darkMode)
            }
            .tabItem { Label("About", systemImage: "info.circle") }
            .tag(AppTab.about)
        }
        .preferredColorScheme(darkMode ? .dark : .light)
    }
}
