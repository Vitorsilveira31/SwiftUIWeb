import SwiftUIWeb

/// Previous, the page numbers around the current one, and Next.
struct SeekrPagination: View {
  let results: SeekrResultsViewModel

  var body: some View {
    HStack(spacing: 8) {
      Button(ResultsStrings.previous) { Task { await results.goTo(results.page - 1) } }
        .buttonStyle(.bordered)
        .disabled(results.page <= 1)
      ForEach(PageNumbers.window(current: results.page, count: results.pageCount), id: \.self) { number in
        Button { Task { await results.goTo(number) } } label: {
          Text("\(number)").fontWeight(number == results.page ? .bold : nil)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
      }
      Button(ResultsStrings.next) { Task { await results.goTo(results.page + 1) } }
        .buttonStyle(.bordered)
        .disabled(results.page >= results.pageCount)
    }
    .frame(maxWidth: .infinity)
  }
}
