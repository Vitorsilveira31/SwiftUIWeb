/// The pages of a result list: how many there are, and the five numbers the pager offers around the current one.
enum PageNumbers {
  static func count(total: Int, size: Int) -> Int { max(1, (total + size - 1) / size) }

  static func window(current: Int, count: Int) -> [Int] {
    let start = max(1, min(current - 2, count - 4))
    let end = min(count, start + 4)
    return Array(start...end)
  }
}
