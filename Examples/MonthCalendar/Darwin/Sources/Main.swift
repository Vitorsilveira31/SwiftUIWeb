import SwiftUI
import MonthCalendar

// The iOS host: only the entry point. The whole app is MonthCalendarRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            MonthCalendarRootView()
        }
    }
}
