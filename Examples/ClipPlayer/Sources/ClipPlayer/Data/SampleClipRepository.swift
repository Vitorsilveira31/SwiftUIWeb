/// The three public sample clips: the first is the default.
struct SampleClipRepository: ClipRepository {
    func clips() -> [Clip] {
        let candidates: [Clip?] = [
            Clip(
                id: "flower",
                title: "Flower",
                detail: "MP4, progressive download",
                urlString: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"
            ),
            Clip(
                id: "bigbuckbunny",
                title: "Big Buck Bunny (HLS)",
                detail: "HLS, adaptive stream",
                urlString: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
            ),
            Clip(
                id: "bipbop",
                title: "Bipbop",
                detail: "HLS, adaptive streaming",
                urlString: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
            ),
        ]
        return candidates.compactMap { $0 }
    }
}
