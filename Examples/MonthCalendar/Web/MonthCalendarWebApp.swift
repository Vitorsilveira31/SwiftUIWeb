import SwiftUIWeb
import SwiftUIWebBrowser
import MonthCalendar

// The browser host: only the entry point. The whole app is MonthCalendarRootView from Sources/MonthCalendar.
@main
struct MonthCalendarWebApp: BrowserApp {
    var body: some View { WindowGroup { MonthCalendarRootView() } }
}
