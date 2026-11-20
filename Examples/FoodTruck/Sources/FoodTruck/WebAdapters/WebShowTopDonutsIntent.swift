// Web adapter, not part of Apple's sample.
//
// Apple's ShowTopDonutsIntent is an App Intent for Siri and Shortcuts, which a browser has neither of. The iPad version's
// Top 5 shows it as a Siri tip (`SiriTipView`); this is the intent as the tip needs it: its timeframe and its phrase.
// Only the browser build compiles it; the Xcode target has Apple's own.
#if WEB
import AppIntents
import FoodTruckKit

struct ShowTopDonutsIntent: SiriTipTitled {
    var timeframe: Timeframe

    var siriTipTitle: String {
        "Food Truck Trends for \(timeframe.siriTipName)"
    }
}

private extension Timeframe {
    var siriTipName: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .month: "This Month"
        case .year: "This Year"
        }
    }
}
#endif
