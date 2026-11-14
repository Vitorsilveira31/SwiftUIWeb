@Environment(\.colorScheme) var scheme
ForEach(rows, id: \.id) { row in Text(row.name) }
ForEach(rows, id: \.self) { row in Text(row.name) }
OutlineGroup(nodes, children: \.children) { node in Text(node.name) }
TableColumn("Name", value: \.name)
TableColumn("Name", value: \Row.name)
KeyframeTrack(\.scale) { LinearKeyframe(1.0, duration: 1) }
let names = rows.map(\.name)
let filtered = rows.filter(\.visible)
"Import failed: \(error)"
"Export failed: \(error)"
