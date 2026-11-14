// Web adapter, not part of Apple's sample.
//
// `Subscription` forwards `Product` and `Product.SubscriptionInfo` members through `@dynamicMemberLookup` with key
// paths, which Embedded Swift (the browser build) does not have. These are the members the sample reads that way; with
// them declared, the sample's own source compiles unchanged.
import Foundation
import StoreKit

extension Subscription {
    public var displayName: String { product.displayName }
    public var description: String { product.description }
    public var displayPrice: String { product.displayPrice }
    public var price: Decimal { product.price }
    public var priceFormatStyle: Product.PriceFormatStyle { product.priceFormatStyle }

    public var subscriptionGroupID: String { subscriptionInfo.subscriptionGroupID }
    public var subscriptionPeriod: Product.SubscriptionPeriod { subscriptionInfo.subscriptionPeriod }
    public var subscriptionPeriodUnitFormatStyle: Product.SubscriptionPeriod.Unit.FormatStyle {
        subscriptionInfo.subscriptionPeriodUnitFormatStyle
    }
}
