import SwiftUIWeb

/// "People also ask": the questions, set apart by a rule, each one a search for its text. No fill: the text keeps the theme's colors.
struct SeekrPeopleAlsoAsk: View {
  let questions: [String]
  let shell: SeekrShellViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()
      Text(ResultsStrings.peopleAlsoAsk).font(.headline).padding(.top, 6)
      ForEach(questions, id: \.self) { question in
        Button { Task { await shell.submit(question) } } label: {
          Text("\(question)?")
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
