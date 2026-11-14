import SwiftUIWeb

/// How the stay screens write dates, prices and ratings. These are number and date formats, not copy, so they need no accessor.
enum StayFormat {
  static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  /// A day as a line shows it: "Nov 3".
  static func day(_ date: Date) -> String {
    let parts = StayDays.civil(date)
    return "\(months[parts.month - 1]) \(parts.day)"
  }

  /// A price in whole dollars: "$120".
  static func price(_ amount: Int) -> String { "$\(amount)" }

  /// A rating in tenths, as it reads: 45 is "4.5".
  static func rating(_ tenths: Int) -> String { "\(tenths / 10).\(tenths % 10)" }
}
