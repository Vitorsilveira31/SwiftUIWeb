import SwiftUIWeb

/// One step: what to do, and the code to do it.
struct StartStepCard: View {
  let step: StartStep

  var body: some View {
    SiteCard {
      SiteBulletRow(title: step.title, detail: step.detail)
      SiteCodeBlock(code: step.code)
    }
  }
}
