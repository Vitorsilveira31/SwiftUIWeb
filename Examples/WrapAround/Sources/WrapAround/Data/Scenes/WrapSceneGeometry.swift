/// A study's exclusion shapes. Pure: the same context always gives the same shapes, so a seek or a
/// resume never depends on earlier frames.
protocol WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion]
}
