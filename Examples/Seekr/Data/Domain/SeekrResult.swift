/// One web result: a post, shown with the site of the user who wrote it (the site's address is the breadcrumb).
struct SeekrResult: Identifiable, Hashable {
  let id: Int
  let title: String
  let site: String
  let link: String
  let snippet: String
}
