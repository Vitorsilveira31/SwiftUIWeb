import SwiftUIWeb

/// The `Table` itself, before a style is applied to it: two columns over the first `count` sample rows.
struct TableCatalogContent: View {
  let count: Int

  var body: some View {
    Table(TableCatalogRow.sample.prefix(count)) {
      TableColumn("Name", value: \TableCatalogRow.name)
      TableColumn("Role", value: \TableCatalogRow.role)
    }
  }
}
