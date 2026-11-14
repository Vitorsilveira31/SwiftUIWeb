import SwiftUI

// The home screen: widgets above a LazyVGrid of tiles, then the dock. A tile with an app
// zooms that app open; the others say they are not in the demo.
struct HomeScreenView: View {
    let home: HomeViewModel
    let shell: ShellViewModel
    let unreadCount: Int
    let zoom: Namespace.ID

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 0) {
                StatusBar()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let event = home.state.event, let forecast = home.state.forecast {
                            HStack(alignment: .top, spacing: 14) {
                                CalendarWidget(event: event)
                                ForecastWidget(forecast: forecast)
                            }
                        }
                        if let lead = home.state.lead {
                            ReaderWidget(article: lead) {
                                shell.send(.openArticle(lead.id))
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(home.state.tiles) { tile in
                                TileButton(
                                    tile: tile,
                                    zoom: zoom,
                                    // The tile is the zoom's source unless its app is the one open.
                                    isSource: shell.state.presentedApp?.rawValue != tile.id,
                                    badge: tile.id == "messages" ? unreadCount : 0
                                ) {
                                    shell.send(.activate(tile.target, name: tile.title))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                Dock(items: home.state.dock, shell: shell)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
