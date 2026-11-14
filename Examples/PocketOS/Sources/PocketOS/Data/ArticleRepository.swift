// Where the articles come from. The app reads them once; a real app would fetch them.
protocol ArticleRepository: Sendable {
    func articles() -> [Article]
}
