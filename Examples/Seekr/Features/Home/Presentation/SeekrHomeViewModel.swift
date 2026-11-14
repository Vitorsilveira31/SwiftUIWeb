import SwiftUIWeb

/// The home page's state: "I am feeling lucky" finds the first result, and says so when there is none.
@MainActor @Observable
final class SeekrHomeViewModel {
  private(set) var notice: String?
  private let feelingLucky: any FeelingLuckyUseCase

  init(feelingLucky: any FeelingLuckyUseCase) { self.feelingLucky = feelingLucky }

  /// The address of the first result for `query`, or nil (with a notice) when there is none or the service could not be reached.
  func luckyLink(for query: String) async -> String? {
    notice = nil
    guard !query.isEmpty else { return nil }
    do {
      if let link = try await feelingLucky.execute(query: query) { return link }
      notice = HomeStrings.noLuckyResult(query)
    } catch {
      notice = FailureText.unreachable
    }
    return nil
  }
}
