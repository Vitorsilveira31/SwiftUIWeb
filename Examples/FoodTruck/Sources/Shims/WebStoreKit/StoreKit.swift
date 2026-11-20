// A browser stand-in for StoreKit 2, so Apple's Food Truck store screens run unmodified.
//
// There is no App Store in a browser. This is a demonstration store over the same three products as the sample's
// Products.storekit: a purchase succeeds at once, entitlements persist in the page's local storage, and the
// subscription status, renewal and refund flows answer from that record. A real store would put a payment provider
// behind the same shapes.
@_spi(Renderer) @_spi(Generated) import SwiftUIWeb

// MARK: Catalog and record

enum DemoStore {
  struct Entry: Sendable {
    let id: String
    let type: Product.ProductType
    let name: String
    let detail: String
    let price: Decimal
    let period: Product.SubscriptionPeriod?
  }

  static let groupID = "20947887"
  static let catalog: [Entry] = [
    Entry(id: "feature.annualhistory", type: .nonConsumable, name: "Full year of history",
          detail: "Data and insights that cover an entire year", price: 0.99, period: nil),
    Entry(id: "socialfeedplus.monthly", type: .autoRenewable, name: "Social Feed+ Monthly Plan",
          detail: "Access advanced social-feed tools", price: 4.99, period: .init(value: 1, unit: .month)),
    Entry(id: "socialfeedplus.yearly", type: .autoRenewable, name: "Social Feed+ Yearly Plan",
          detail: "Advanced tools at a greater value", price: 49.99, period: .init(value: 1, unit: .year))
  ]

  private static let key = "foodtruck.demostore.purchases"

  /// Latest purchase date the record accepts (2100-01-01). Local storage is editable, so other values are dropped.
  private static let maxEpochSeconds: Double = 4_102_444_800

  /// `id:epochSeconds` pairs, newest last.
  static var purchases: [(id: String, date: Date)] {
    guard let stored = UserDefaults.standard.string(forKey: key) else { return [] }
    return stored.split(separator: ",").compactMap { pair in
      let parts = pair.split(separator: ":")
      guard parts.count == 2, let seconds = Double(parts[1]),
            seconds.isFinite, seconds >= 0, seconds <= maxEpochSeconds else { return nil }
      return (String(parts[0]), Date(timeIntervalSince1970: seconds))
    }
  }

  /// Whole epoch seconds as 64 bits: Int is 32 bits in the browser build, and a conversion of an out-of-range date traps.
  static func epochSeconds(_ date: Date) -> Int64? {
    let seconds = date.timeIntervalSince1970.rounded(.down)
    guard seconds.isFinite, seconds >= 0, seconds <= maxEpochSeconds else { return nil }
    return Int64(seconds)
  }

  static func transactionID(for date: Date) -> UInt64 {
    UInt64(epochSeconds(date) ?? 0)
  }

  static func record(_ id: String, at date: Date = Date()) {
    var current = purchases.filter { $0.id != id }
    current.append((id, date))
    save(current)
  }

  static func remove(_ id: String) { save(purchases.filter { $0.id != id }) }

  private static func save(_ list: [(id: String, date: Date)]) {
    let text = list.compactMap { item in epochSeconds(item.date).map { "\(item.id):\($0)" } }.joined(separator: ",")
    UserDefaults.standard.set(text, forKey: key)
  }

  static func entry(_ id: String) -> Entry? { catalog.first { $0.id == id } }

  static func transaction(for id: String, at date: Date) -> Transaction {
    let entry = entry(id)
    let period = entry?.period
    var expiration: Date?
    if let period {
      let seconds: Double = period.unit == .year ? 31_536_000 : 2_592_000
      expiration = date.addingTimeInterval(seconds * Double(period.value))
    }
    return Transaction(id: transactionID(for: date), productID: id, productType: entry?.type ?? .nonConsumable,
                       purchaseDate: date, expirationDate: expiration, revocationDate: nil)
  }
}

// MARK: Verification

public enum VerificationResult<SignedType: Sendable>: Sendable {
  public enum VerificationError: Error, Sendable { case invalidSignature }

  case unverified(SignedType, VerificationError)
  case verified(SignedType)

  public var unsafePayloadValue: SignedType {
    switch self {
    case .verified(let value), .unverified(let value, _): return value
    }
  }

  public var payloadValue: SignedType {
    get throws {
      switch self {
      case .verified(let value): return value
      case .unverified(_, let error): throw error
      }
    }
  }
}

// MARK: Product

public struct Product: Identifiable, Hashable, Sendable {
  public enum ProductType: Hashable, Sendable { case consumable, nonConsumable, nonRenewable, autoRenewable }

  public enum PurchaseResult: Sendable {
    case success(VerificationResult<Transaction>)
    case userCancelled
    case pending
  }

  public struct SubscriptionPeriod: Hashable, Sendable {
    public enum Unit: Hashable, Sendable {
      case day, week, month, year

      public var localizedDescription: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
      }

      /// Formats the unit as the plural-free word a price line shows ("month").
      public func formatted<S: SwiftUIWebInternationalization.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Unit {
        style.format(self)
      }

      public struct FormatStyle: SwiftUIWebInternationalization.FormatStyle, Hashable, Sendable {
        public func format(_ value: Unit) -> String { value.localizedDescription.lowercased() }
      }
    }

    public let value: Int
    public let unit: Unit
  }

  public struct SubscriptionInfo: Hashable, Sendable {
    public enum RenewalState: Hashable, Sendable { case subscribed, expired, inBillingRetryPeriod, inGracePeriod, revoked }

    public struct RenewalInfo: Hashable, Sendable {
      public let currentProductID: String
      public let autoRenewPreference: String?
    }

    public struct Status: Sendable {
      public let transaction: VerificationResult<Transaction>
      public let renewalInfo: VerificationResult<RenewalInfo>
      public let state: RenewalState

      /// Subscription status changes; the demonstration store reports them through the purchase flow instead.
      public static var updates: AsyncStream<Status> { AsyncStream { _ in } }
    }

    public let subscriptionGroupID: String
    public let subscriptionPeriod: SubscriptionPeriod

    public var subscriptionPeriodUnitFormatStyle: SubscriptionPeriod.Unit.FormatStyle { .init() }

    public var isEligibleForIntroOffer: Bool { get async { false } }

    public static func status(for groupID: String) async throws -> [Status] {
      guard groupID == DemoStore.groupID else { return [] }
      let owned = DemoStore.purchases.filter { DemoStore.entry($0.id)?.type == .autoRenewable }
      guard let latest = owned.last else { return [] }
      let transaction = DemoStore.transaction(for: latest.id, at: latest.date)
      return [Status(transaction: .verified(transaction),
                     renewalInfo: .verified(RenewalInfo(currentProductID: latest.id, autoRenewPreference: latest.id)),
                     state: .subscribed)]
    }
  }

  public let id: String
  public let type: ProductType
  public let displayName: String
  public let description: String
  public let price: Decimal
  public let subscription: SubscriptionInfo?

  /// "$4.99", as the demonstration store prices everything in US dollars.
  public var displayPrice: String { price.formatted(priceFormatStyle) }

  public var priceFormatStyle: PriceFormatStyle { PriceFormatStyle() }

  public struct PriceFormatStyle: SwiftUIWebInternationalization.FormatStyle, Hashable, Sendable {
    public func format(_ value: Decimal) -> String {
      let cents = Int((Double(value) * 100).rounded())
      let fraction = cents % 100
      return "$\(cents / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
  }

  public static func products<IDs: Collection>(for identifiers: IDs) async throws -> [Product] where IDs.Element == String {
    DemoStore.catalog.filter { identifiers.contains($0.id) }.map { entry in
      Product(id: entry.id, type: entry.type, displayName: entry.name, description: entry.detail, price: entry.price,
              subscription: entry.period.map { SubscriptionInfo(subscriptionGroupID: DemoStore.groupID, subscriptionPeriod: $0) })
    }
  }

  public func purchase() async throws -> PurchaseResult {
    let date = Date()
    DemoStore.record(id, at: date)
    return .success(.verified(DemoStore.transaction(for: id, at: date)))
  }
}

// MARK: Transactions

public struct Transaction: Identifiable, Hashable, Sendable {
  public let id: UInt64
  public let productID: String
  public let productType: Product.ProductType
  public let purchaseDate: Date
  public let expirationDate: Date?
  public let revocationDate: Date?

  public func finish() async {}

  public enum RefundRequestStatus: Sendable { case success, userCancelled }
  public enum RefundRequestError: Error, Sendable { case failed }

  public static var updates: AsyncStream<VerificationResult<Transaction>> { AsyncStream { _ in } }

  public static var all: AsyncStream<VerificationResult<Transaction>> {
    let list = DemoStore.purchases.reversed().map { VerificationResult.verified(DemoStore.transaction(for: $0.id, at: $0.date)) }
    return AsyncStream { continuation in
      for item in list { continuation.yield(item) }
      continuation.finish()
    }
  }

  public static func currentEntitlement(for productID: String) async -> VerificationResult<Transaction>? {
    guard let purchase = DemoStore.purchases.last(where: { $0.id == productID }) else { return nil }
    return .verified(DemoStore.transaction(for: productID, at: purchase.date))
  }
}

// MARK: Store, storefront

public enum AppStore {
  /// Restoring purchases: the record is already local, so there is nothing to fetch.
  public static func sync() async throws {}
}

public struct Storefront: Hashable, Sendable {
  public let id: String
  public let countryCode: String
  public static var updates: AsyncStream<Storefront> { AsyncStream { _ in } }
}

// MARK: Sheets

public extension View {
  /// The system's subscription management sheet, as a demonstration: it lists the active plan and can cancel it.
  func manageSubscriptionsSheet(isPresented: Binding<Bool>) -> some View {
    sheet(isPresented: isPresented) { DemoManageSubscriptionsSheet(isPresented: isPresented) }
  }

  /// The system's offer code sheet (the iPad version's "Redeem an Offer Code"), as a demonstration: there is no App Store
  /// to check a code against, so the sheet says so and closes.
  func offerCodeRedemption(
    isPresented: Binding<Bool>, onCompletion: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }
  ) -> some View {
    sheet(isPresented: isPresented) { DemoOfferCodeSheet(isPresented: isPresented, onCompletion: onCompletion) }
  }

  /// The system's refund request sheet, as a demonstration: confirming removes the purchase.
  func refundRequestSheet(
    for transactionID: UInt64, isPresented: Binding<Bool>,
    onDismiss: (@MainActor (Result<Transaction.RefundRequestStatus, Transaction.RefundRequestError>) -> Void)? = nil
  ) -> some View {
    sheet(isPresented: isPresented) {
      DemoRefundSheet(transactionID: transactionID, isPresented: isPresented, onDismiss: onDismiss)
    }
  }
}

private struct DemoManageSubscriptionsSheet: View {
  @Binding var isPresented: Bool
  @State private var plans: [Product] = []

  var body: some View {
    VStack(spacing: 16) {
      Text("Manage subscriptions").font(.headline)
      if plans.isEmpty {
        Text("You have no active subscriptions.").foregroundStyle(.secondary)
      }
      ForEach(plans) { plan in
        HStack {
          VStack(alignment: .leading) {
            Text(plan.displayName)
            Text(plan.displayPrice).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Cancel plan") {
            DemoStore.remove(plan.id)
            plans.removeAll { $0.id == plan.id }
          }
        }
      }
      Button("Done") { isPresented = false }
    }
    .padding(24)
    .frame(minWidth: 320)
    .task {
      let ids = Set(DemoStore.purchases.map(\.id))
      plans = ((try? await Product.products(for: ids)) ?? []).filter { $0.type == .autoRenewable }
    }
  }
}

private struct DemoRefundSheet: View {
  let transactionID: UInt64
  @Binding var isPresented: Bool
  let onDismiss: (@MainActor (Result<Transaction.RefundRequestStatus, Transaction.RefundRequestError>) -> Void)?

  var body: some View {
    VStack(spacing: 16) {
      Text("Request a refund").font(.headline)
      Text("The demonstration store refunds immediately.").foregroundStyle(.secondary)
      HStack {
        Button("Not now") {
          isPresented = false
          onDismiss?(.success(.userCancelled))
        }
        Button("Refund") {
          if let purchase = DemoStore.purchases.first(where: { DemoStore.transactionID(for: $0.date) == transactionID }) {
            DemoStore.remove(purchase.id)
          }
          isPresented = false
          onDismiss?(.success(.success))
        }
      }
    }
    .padding(24)
    .frame(minWidth: 320)
  }
}

// MARK: Review prompts

/// `@Environment(\.requestReview)`. A browser has no store review prompt; calling it does nothing.
public struct RequestReviewAction: Sendable {
  @MainActor public func callAsFunction() {}
}

private enum RequestReviewEnvironmentKey: EnvironmentKey { static let defaultValue = RequestReviewAction() }

public extension EnvironmentValues {
  var requestReview: RequestReviewAction {
    get { self[RequestReviewEnvironmentKey.self] }
    set { self[RequestReviewEnvironmentKey.self] = newValue }
  }
}

// MARK: App Store messages

/// A message the App Store asks the app to show (a price increase, a billing issue). No store sends one to a browser, so
/// `messages` ends at once; the iPad version of Food Truck (`os(iOS)`) waits on it and finds none.
public struct Message: Sendable {
  public enum Reason: Hashable, Sendable { case generic, priceIncreaseConsent, billingIssue, winBackOffer }
  public let reason: Reason
  public static var messages: AsyncStream<Message> { AsyncStream { $0.finish() } }
}

/// Shows an App Store message (`displayStoreKitMessage`). There is none to show in a browser.
public struct DisplayMessageAction: Sendable {
  @MainActor public func callAsFunction(_ message: Message) throws {}
}

private enum DisplayStoreKitMessageEnvironmentKey: EnvironmentKey { static let defaultValue = DisplayMessageAction() }

public extension EnvironmentValues {
  var displayStoreKitMessage: DisplayMessageAction {
    get { self[DisplayStoreKitMessageEnvironmentKey.self] }
    set { self[DisplayStoreKitMessageEnvironmentKey.self] = newValue }
  }
}

/// `offerCodeRedemption`'s sheet in the browser.
struct DemoOfferCodeSheet: View {
  @Binding var isPresented: Bool
  let onCompletion: @MainActor (Result<Void, Error>) -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        Image(systemName: "giftcard")
          .font(.system(size: 44))
          .foregroundStyle(.tint)
        Text("Offer codes are redeemed in the App Store.")
          .font(.headline)
        Text("This demonstration store has no codes to check.")
          .foregroundStyle(.secondary)
      }
      .padding(32)
      .navigationTitle("Redeem Code")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            isPresented = false
            onCompletion(.success(()))
          }
        }
      }
    }
  }
}
