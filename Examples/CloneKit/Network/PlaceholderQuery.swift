/// Percent-encoding for a value in a query string, by hand: Embedded Swift has no `addingPercentEncoding`.
enum PlaceholderQuery {
  static func encode(_ text: String) -> String {
    let hex = Array("0123456789ABCDEF")
    var out = ""
    for byte in text.utf8 {
      let isPlain = (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 45 || byte == 46 || byte == 95 || byte == 126
      if isPlain {
        out.append(Character(UnicodeScalar(byte)))
      } else {
        out.append("%")
        out.append(hex[Int(byte >> 4)])
        out.append(hex[Int(byte & 15)])
      }
    }
    return out
  }
}
