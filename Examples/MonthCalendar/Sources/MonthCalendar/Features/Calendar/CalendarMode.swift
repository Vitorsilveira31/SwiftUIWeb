enum CalendarMode: CaseIterable, Identifiable {
    case month, agenda

    var id: Self { self }

    var title: String {
        switch self {
        case .month: return Strings.Screen.modeMonth
        case .agenda: return Strings.Screen.modeAgenda
        }
    }
}
