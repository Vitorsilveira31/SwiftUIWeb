enum Sample: CaseIterable, Identifiable, Sendable, Hashable {
    case welcome, longDocument, tablesAndCode

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome: return Strings.SampleOption.welcome
        case .longDocument: return Strings.SampleOption.longDocument
        case .tablesAndCode: return Strings.SampleOption.tablesAndCode
        }
    }
}
