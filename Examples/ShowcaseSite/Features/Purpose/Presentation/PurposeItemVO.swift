/// A claim on the purpose page: a short statement and the sentence behind it. `symbol`, when set, is the card's own mark
/// instead of the one its section gives every card.
struct PurposeItemVO {
  let id: String
  let title: String
  let detail: String
  var symbol: String? = nil
}
