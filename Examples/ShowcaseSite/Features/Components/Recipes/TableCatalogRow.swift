/// One row of the table catalog's sample data: a name and a role for each column.
struct TableCatalogRow: Identifiable {
  let id: Int
  let name: String
  let role: String

  static let sample = [
    TableCatalogRow(id: 1, name: "Ana", role: "Design"),
    TableCatalogRow(id: 2, name: "Bruno", role: "Engineering"),
    TableCatalogRow(id: 3, name: "Carla", role: "Product"),
    TableCatalogRow(id: 4, name: "Diego", role: "Support"),
    TableCatalogRow(id: 5, name: "Elisa", role: "Sales"),
    TableCatalogRow(id: 6, name: "Fábio", role: "Data"),
  ]
}
