/// What the HTML parser does with a start tag, as far as the binary encoder has to know. The builder makes the DOM the
/// parser makes of the markup of the same tree, for a tree the parser keeps as it is written. Where the parser would move,
/// drop or turn a start tag into another (a second `form` in a `form`, a `div` in a `p`, a `td` outside a table),
/// `BinaryFiberEncoder` writes a tree the parser keeps instead (its `Placement`).
///
/// The facts are bits looked up by the index of the tag in the string table: every name listed here is an atom.
enum BinaryParserFacts {
  /// Closes an open `p`: `address`, `div`, `ul`, the headings...
  static let closesParagraph: UInt32 = 1 << 0
  /// The special elements but `address`, `div` and `p`: where the search for an open `li`, `dd` or `dt` stops.
  static let blocksListScan: UInt32 = 1 << 1
  static let paragraph: UInt32 = 1 << 2
  static let listItem: UInt32 = 1 << 3
  static let definition: UInt32 = 1 << 4
  static let form: UInt32 = 1 << 5
  static let anchor: UInt32 = 1 << 6
  static let heading: UInt32 = 1 << 7
  static let table: UInt32 = 1 << 8
  static let tableSection: UInt32 = 1 << 9
  static let tableRow: UInt32 = 1 << 10
  static let tableCell: UInt32 = 1 << 11
  static let caption: UInt32 = 1 << 12
  static let columnGroup: UInt32 = 1 << 13
  static let column: UInt32 = 1 << 14
  static let select: UInt32 = 1 << 15
  static let optionGroup: UInt32 = 1 << 16
  static let option: UInt32 = 1 << 17
  static let nobr: UInt32 = 1 << 18
  /// Ends the SVG or MathML content it appears in: the parser moves the element out of it.
  static let breaksOutOfForeign: UInt32 = 1 << 19
  /// The parser never makes an element of it where it is written.
  static let neverBuilt: UInt32 = 1 << 20
  /// May sit directly in a `table`, a table section or a row.
  static let allowedInTable: UInt32 = 1 << 21
  /// May sit directly in a `select`.
  static let allowedInSelect: UInt32 = 1 << 22
  /// Starts SVG or MathML content when the parser makes it among HTML.
  static let startsSvg: UInt32 = 1 << 23
  static let startsMathML: UInt32 = 1 << 24
  /// Has no content and no end tag.
  static let isVoid: UInt32 = 1 << 25
  /// An element whose DOM state the host keeps (typed text, open or closed, playback...): its attributes are sent again
  /// whenever it is visited.
  static let hostOwned: UInt32 = 1 << 26
  /// The placeholder the snapshot writes for an element the host holds.
  static let isKeep: UInt32 = 1 << 27
  /// Elements that keep white space and nothing else among their children: the parser moves text out of them.
  static let tableContent: UInt32 = table | tableSection | tableRow | columnGroup

  private static let rules: [(names: StaticString, facts: UInt32)] = [
    ("address article aside blockquote center details dialog dir div dl fieldset figcaption figure footer header hgroup main menu nav ol p section summary ul h1 h2 h3 h4 h5 h6 pre listing form table hr xmp plaintext li dd dt", closesParagraph),
    ("article aside blockquote body br button caption center col colgroup dd details dialog dir dl dt embed fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hgroup hr html iframe img input li listing main menu meta nav noembed noframes noscript ol plaintext pre script section select source style summary table tbody td template textarea tfoot th thead title tr track ul xmp foreignObject desc mi mo mn ms mtext annotation-xml", blocksListScan),
    ("p", paragraph), ("li", listItem), ("dd dt", definition), ("form", form), ("a", anchor), ("h1 h2 h3 h4 h5 h6", heading),
    ("table", table), ("thead tbody tfoot", tableSection), ("tr", tableRow), ("td th", tableCell), ("caption", caption),
    ("colgroup", columnGroup), ("col", column), ("select", select), ("optgroup", optionGroup), ("option", option), ("nobr", nobr),
    ("b big blockquote body br center code dd div dl dt em embed h1 h2 h3 h4 h5 h6 head hr i img li listing menu meta nobr ol p pre ruby s small span strong strike sub sup table tt u ul var font", breaksOutOfForeign),
    ("html head body frame frameset plaintext isindex", neverBuilt),
    ("style script template", allowedInTable), ("hr script template", allowedInSelect), ("svg", startsSvg), ("math", startsMathML),
    ("area base br col embed hr img input link meta param source track wbr", isVoid),
    ("input textarea select option details dialog video audio canvas iframe object embed", hostOwned), ("keep", isKeep),
  ]

  /// The facts of each atom, by atom index: worked out once.
  static let byAtom: [UInt32] = {
    let atoms = BinaryAtomTable.shared
    var facts = [UInt32](repeating: 0, count: atoms.count)
    for rule in rules {
      let bytes = rule.names.utf8Start
      var begin = 0
      var index = 0
      while index <= rule.names.utf8CodeUnitCount {
        if index == rule.names.utf8CodeUnitCount || bytes[index] == 32 {
          if let atom = atoms.index(bytes + begin, count: index - begin, hash: BinaryAtomTable.hash(bytes + begin, count: index - begin)) { facts[Int(atom)] |= rule.facts }
          begin = index + 1
        }
        index += 1
      }
    }
    return facts
  }()
}
