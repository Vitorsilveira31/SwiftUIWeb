import Observation

let raw = #"ForEach(rows, id: \.id) { { not code } }"#
/* Braces in comments must not affect declaration matching. */
@MainActor @Observable final class Complex<T> where T: Equatable {
  @ObservationIgnored private var cache: [String: T] = [:]
  private(set) var values: [String: [Int: T]]
  var title: String = "{still a string}"
  var computed: String { title }
}

@Observable final class Second { var count = 0 }
