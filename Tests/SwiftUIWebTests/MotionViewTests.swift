import Foundation
import Testing
import SwiftUIWeb
import SwiftUIWebMotion

@Suite
@MainActor
final class MotionViewTests {
  private let animation = """
    {"v":"5.7.4","fr":29.97,"ip":10,"op":70,"w":320,"h":180.5,"nm":"a \\"quoted\\" name","assets":[{"id":"x","layers":[{"ip":99,"op":1}]}],\
    "layers":[{"ty":4,"ip":0,"op":70,"ks":{"p":{"k":[1,2,3]}},"nm":"}{]["}],"markers":[]}
    """

  @Test
  func testLottieContainerReadsTheCompositionHeader() throws {
    let container = try LottieContainer(data: Data(animation.utf8))
    _expectTrue(container.startFrame == 10)
    _expectTrue(container.endFrame == 70)
    _expectTrue(abs(container.framerate - 29.97) < 1e-9)
    _expectTrue(abs(container.duration - 60 / 29.97) < 1e-9)
    _expectTrue(container.width == 320)
    _expectTrue(container.height == 180.5)
    _expectTrue(container.bounds == CGRect(x: 0, y: 0, width: 320, height: 180.5))
  }

  @Test
  func testLottieContainerReadsExponentsAndNegativeNumbers() throws {
    let json = #"{ "ip": -1.5e1, "op": 6E1, "fr": 3.0e+1, "w": 1e2, "h": 50, "layers": [] }"#
    let container = try LottieContainer(data: Data(json.utf8))
    _expectTrue(container.startFrame == -15)
    _expectTrue(container.endFrame == 60)
    _expectTrue(container.framerate == 30)
    _expectTrue(container.width == 100)
  }

  @Test
  func testLottieContainerRefusesWhatIsNotAnAnimation() {
    for text in ["", "[]", "{}", "not json", #"{"ip":0,"op":60,"fr":30}"#, #"{"ip":0,"op":0,"fr":30,"layers":[]}"#,
                 #"{"ip":0,"op":60,"fr":0,"layers":[]}"#, #"{"ip":0,"op":60,"fr":30,"layers":[}"#, #"{"ip":0,"op":60,"fr":30,"layers":[]"#] {
      _expectTrue((try? LottieContainer(data: Data(text.utf8))) == nil, "accepted \(text)")
    }
  }

  @Test
  func testMotionViewRendersWhatTheHostPlays() throws {
    let container = try LottieContainer(data: Data(animation.utf8))
    let playing = StaticHTMLFiberRenderer().render(
      MotionView(lottie: container, animationSpeed: 2, loopMode: .repeatBackwards(3), contentMode: .fill, fromProgress: 0.25, toProgress: 0.5)
    )
    _expectTrue(playing.contains("class=\"motion-view\""))
    _expectTrue(playing.contains("data-host-managed=\"*children\""))
    _expectTrue(playing.contains("data-motion-mode=\"play\""))
    _expectTrue(playing.contains("data-motion-loop=\"repeat-backwards:3\""))
    _expectTrue(playing.contains("data-motion-speed=\"2.0\""))
    _expectTrue(playing.contains("data-motion-from=\"0.25\""))
    _expectTrue(playing.contains("data-motion-to=\"0.5\""))
    _expectTrue(playing.contains("data-motion-content-mode=\"fill\""))
    _expectTrue(playing.contains("data-motion-animation="))

    // A range that does not run forward is not a range, as for lottie-ios; paused, the progress wins over the frame.
    let backwards = StaticHTMLFiberRenderer().render(MotionView(lottie: container, fromProgress: 0.5, toProgress: 0.25))
    _expectTrue(!backwards.contains("data-motion-from"))
    _expectTrue(backwards.contains("data-motion-loop=\"loop\""))
    let paused = StaticHTMLFiberRenderer().render(MotionView(lottie: container, isPlaying: false, currentProgress: 0.3, currentFrame: 12))
    _expectTrue(paused.contains("data-motion-mode=\"pause\""))
    _expectTrue(paused.contains("data-motion-progress=\"0.3\""))
    _expectTrue(!paused.contains("data-motion-frame"))
    let frame = StaticHTMLFiberRenderer().render(MotionView(lottie: container, isPlaying: false, currentFrame: 12))
    _expectTrue(frame.contains("data-motion-frame=\"12.0\""))
  }

  @Test
  func testMotionViewOverDataThatIsNotAnAnimationDrawsNothing() {
    let html = StaticHTMLFiberRenderer().render(VStack { MotionView(lottie: Data("{}".utf8)) })
    _expectTrue(!html.contains("motion-view"))
  }
}
