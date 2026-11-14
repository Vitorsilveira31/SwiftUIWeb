/// Where the player gets the clips it can play.
protocol ClipRepository {
    func clips() -> [Clip]
}
