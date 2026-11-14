/// Counts the way a feed writes them: 1,284 stays whole, 12,400 becomes 12.4K, 1,300,000 becomes 1.3M.
enum Numbers {
  static func compact(_ value: Int) -> String {
    if value >= 1_000_000 { return "\(value / 1_000_000).\((value % 1_000_000) / 100_000)M" }
    if value >= 10_000 { return "\(value / 1_000).\((value % 1_000) / 100)K" }
    return value >= 1_000 ? "\(value / 1_000),\(pad(value % 1_000))" : "\(value)"
  }

  private static func pad(_ remainder: Int) -> String {
    remainder < 10 ? "00\(remainder)" : remainder < 100 ? "0\(remainder)" : "\(remainder)"
  }
}
