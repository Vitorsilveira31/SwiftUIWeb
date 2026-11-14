/// A person with what their profile shows: their albums as highlights and the pictures of the first.
struct LumioProfile {
  let user: LumioUser
  let postCount: Int
  let albumTitles: [String]
  let tiles: [LumioTile]
}
