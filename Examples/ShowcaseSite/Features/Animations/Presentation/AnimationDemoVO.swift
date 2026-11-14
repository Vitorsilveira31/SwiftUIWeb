/// What one animation card says about itself: a name, a sentence about it and the code it runs.
struct AnimationDemoVO: Equatable, Identifiable {
  let id: String
  let title: String
  let detail: String
  let code: String
}
