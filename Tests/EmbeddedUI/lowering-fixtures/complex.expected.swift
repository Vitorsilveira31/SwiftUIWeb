@_spi(Renderer) import SwiftUIWeb

let raw = #"ForEach(rows, id: \.id) { { not code } }"#
/* Braces in comments must not affect declaration matching. */
@MainActor  final class Complex<T> where T: Equatable {
  private var cache: [String: T] = [:]
  @Published(memberID: 1) private(set) var values: [String: [Int: T]]
  @Published(memberID: 2) var title: String = "{still a string}"
  var computed: String { title }
}

 final class Second { @Published(memberID: 1) var count = 0 }
