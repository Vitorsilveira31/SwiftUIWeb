import Foundation
import Testing
import SwiftUIWeb
@testable import SwiftUIWebAVFoundation
@testable import SwiftUIWebAVKit

/// The control bar's subtitles and audio menus: what they list, which option is checked, and that choosing one goes through
/// `AVPlayerItem.select(_:in:)` (the controls only send `caption|…` and `audio|…`; the item stays the source of truth).
@Suite
@MainActor
struct AVKitSelectionMenuTests {
  /// A plain file with two `<track>` elements (the English one is the browser's default), as the media host reports them.
  private let captions = ["t\t0\ten\tEnglish\t1", "t\t1\tpt\tPortuguês\t0"].joined(separator: "\n")

  private func player() -> AVPlayer {
    AVPlayer(url: URL(string: "https://media.example/clip.mp4")!)
  }

  private func asset(of player: AVPlayer) -> AVURLAsset {
    player.currentItem!.asset as! AVURLAsset
  }

  @Test func a_stream_without_alternatives_has_no_menus() {
    let player = player()
    let model = AVKitControlsModel(player: player)
    #expect(model.captions == nil)
    #expect(model.audio == nil)
  }

  @Test func the_subtitles_menu_lists_off_and_the_tracks_with_the_default_checked() {
    let player = player()
    asset(of: player)._receiveTracks(captions)
    let menu = AVKitControlsModel(player: player).captions
    #expect(menu?.entries.map(\.id) == ["off", "0", "1"])
    #expect(menu?.entries.map(\.label) == ["Off", "English", "Português"])
    #expect(menu?.entries.map(\.isChecked) == [false, true, false], "the browser's default track is what plays")
    #expect(menu?.checkedLabel == "English")
    #expect(AVKitControlsModel(player: player).audio == nil, "a plain file has no alternate audio")
  }

  @Test func choosing_a_track_selects_it_on_the_item_and_off_turns_subtitles_off() throws {
    let player = player()
    asset(of: player)._receiveTracks(captions)

    AVKitControlsAction.perform("caption|1", on: player)
    let group = try #require(player.currentItem?._selectionGroup(for: .legible))
    #expect(player.currentItem?.currentMediaSelection.selectedMediaOption(in: group)?._identifier == "1")
    var menu = try #require(AVKitControlsModel(player: player).captions)
    #expect(menu.entries.map(\.isChecked) == [false, false, true])
    #expect(menu.checkedLabel == "Português")

    AVKitControlsAction.perform("caption|off", on: player)
    menu = try #require(AVKitControlsModel(player: player).captions)
    #expect(menu.entries.map(\.isChecked) == [true, false, false], "Off is checked once subtitles are turned off")

    AVKitControlsAction.perform("caption|99", on: player)
    menu = try #require(AVKitControlsModel(player: player).captions)
    #expect(menu.entries.map(\.isChecked) == [true, false, false], "an unknown track changes nothing")
  }

  @Test func the_choice_survives_a_later_report_of_the_same_tracks() throws {
    let player = player()
    asset(of: player)._receiveTracks(captions)
    AVKitControlsAction.perform("caption|1", on: player)
    // The host reports again (a track's mode changed): the item keeps what Swift chose.
    asset(of: player)._receiveTracks(captions)
    let menu = try #require(AVKitControlsModel(player: player).captions)
    #expect(menu.entries.map(\.isChecked) == [false, false, true])
  }

  @Test func the_audio_menu_appears_for_alternate_audio_and_has_no_off() throws {
    let player = player()
    asset(of: player)._receiveTracks(["a\tpt/main\tpt\tPortuguês\t1", "a\ten/\ten\tEnglish\t0"].joined(separator: "\n"))
    let menu = try #require(AVKitControlsModel(player: player).audio)
    #expect(menu.entries.map(\.id) == ["pt/main", "en/"])
    #expect(menu.entries.map(\.isChecked) == [true, false])
    #expect(AVKitControlsModel(player: player).captions == nil)

    AVKitControlsAction.perform("audio|en/", on: player)
    let chosen = try #require(AVKitControlsModel(player: player).audio)
    #expect(chosen.entries.map(\.isChecked) == [false, true])
    AVKitControlsAction.perform("audio|off", on: player)
    #expect(AVKitControlsModel(player: player).audio?.entries.map(\.isChecked) == [false, true], "audio has no off: the choice stays")
  }

  @Test func the_controls_render_the_menus_as_menus() {
    let player = player()
    let plain = StaticHTMLFiberRenderer().render(VideoPlayer(player: player))
    _expectFalse(plain.contains("avkit-captions"), "no subtitles button without subtitle tracks")

    asset(of: player)._receiveTracks(captions)
    let html = StaticHTMLFiberRenderer().render(VideoPlayer(player: player))
    _expectTrue(html.contains("class=\"avkit-button avkit-captions\""))
    _expectTrue(html.contains("aria-label=\"Subtitles and Captions, English\""))
    _expectTrue(html.contains("role=\"menu\""))
    _expectTrue(html.contains("data-control-action=\"caption\" data-control-argument=\"off\""))
    _expectTrue(html.contains("role=\"menuitemradio\""))
    _expectTrue(html.contains("aria-checked=\"true\""))
    _expectFalse(html.contains("avkit-audio-group"), "no audio button without alternate audio")
  }
}
