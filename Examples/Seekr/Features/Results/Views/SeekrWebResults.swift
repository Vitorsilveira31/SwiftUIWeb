import SwiftUIWeb

/// The results of the open tab: the count, the cards, the questions people ask (All only), and the pager. Loading, failed and empty
/// states replace the list.
struct SeekrWebResults: View {
  let shell: SeekrShellViewModel

  var body: some View {
    let results = shell.results
    VStack(alignment: .leading, spacing: 18) {
      if results.state != .loaded {
        SeekrStatusView(state: results.state, loading: ResultsStrings.loading, failedTitle: ResultsStrings.failedTitle, retry: ResultsStrings.retry) {
          Task { await results.retry() }
        }
      } else if results.results.isEmpty {
        Text(ResultsStrings.noResults(results.query)).foregroundStyle(.secondary).padding(.vertical, 32)
      } else {
        Text(ResultsStrings.count(results.total)).font(.caption).foregroundStyle(.secondary)
        ForEach(results.results) { result in
          SeekrResultCard(result: result, query: results.query)
        }
        if results.tab == .all && !results.questions.isEmpty {
          SeekrPeopleAlsoAsk(questions: results.questions, shell: shell)
        }
        if results.pageCount > 1 {
          SeekrPagination(results: results)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
