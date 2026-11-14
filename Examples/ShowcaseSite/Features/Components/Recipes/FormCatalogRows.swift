import SwiftUIWeb

/// The rows of the form's section, alternating a `Toggle` and a `TextField`, as many as the knob asks for (up to four).
struct FormCatalogRows: View {
  let count: Int

  var body: some View {
    if count >= 1 { FormCatalogToggleRow(number: 1) }
    if count >= 2 { FormCatalogTextRow(number: 2) }
    if count >= 3 { FormCatalogToggleRow(number: 3) }
    if count >= 4 { FormCatalogTextRow(number: 4) }
  }
}
