@_spi(Renderer) import SwiftUIWeb
@Environment(_embedded: { $0.colorScheme }) var scheme
ForEach(rows, id: { $0.id }) { row in Text(row.name) }
ForEach(rows, id: { $0 }) { row in Text(row.name) }
OutlineGroup(nodes, _embeddedChildren: { $0.children }) { node in Text(node.name) }
TableColumn("Name") { row in Text(row.name) }
TableColumn("Name") { (row: Row) in Text(row.name) }
KeyframeTrack(_embeddedMember: "scale", _embeddedGet: { $0.scale }, _embeddedSet: { $0.scale = $1 }) { LinearKeyframe(1.0, duration: 1) }
let names = rows.map { $0.name }
let filtered = rows.filter { $0.visible }
"Import failed"
"Export failed"
