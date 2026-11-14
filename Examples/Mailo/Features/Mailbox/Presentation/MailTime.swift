/// When a message was sent, from its id: the service keeps no clock, so the id stands in for one and the same id always gives the same time.
enum MailTime {
  /// "14:05" for a message of today, "Yesterday", or the date ("Oct 22") for an older one. The day is 29 October 2026.
  static func label(for id: Int) -> String {
    // Wrapping multiply on the magnitude: ids can be large, and Int is 32 bits in the browser build.
    let daysAgo = Int((id.magnitude &* 3) % 14)
    if daysAgo == 1 { return MailboxStrings.yesterday }
    if daysAgo > 1 { return MailboxStrings.date(day: 29 - daysAgo) }
    let minute = Int((id.magnitude &* 379) % UInt(24 * 60))
    return "\(twoDigits(minute / 60)):\(twoDigits(minute % 60))"
  }

  private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
