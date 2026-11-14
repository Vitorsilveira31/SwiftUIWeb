import Foundation
import Testing
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@testable import SwiftUIWebAVFoundation

/// Subtitles, audio languages and renditions with AVFoundation's API: the host reports a stream's
/// tracks, the item's choices render as attributes the host applies.
@Suite
@MainActor
struct AVMediaSelectionTests {
  private let tracks = [
    "v\t1080\t1920\t6000000", "v\t720\t1280\t3000000",
    "a\tpt/main\tpt\tPortuguês\t1", "a\ten/\ten\t\t0",
    "t\t7\tpt\tPortuguês\t0", "t\t8\ten\tEnglish\t0",
  ].joined(separator: "\n")

  private func player() -> (AVPlayer, AVURLAsset, _RenderNode) {
    let player = AVPlayer(url: URL(string: "https://media.example/pilot/index.m3u8")!)
    let node = VideoPlayer(player: player, showsPlaybackControls: false)._render(in: _RenderContext())
    return (player, player.currentItem!.asset as! AVURLAsset, node)
  }

  @Test func loading_waits_for_the_host_and_reads_its_tracks() async throws {
    let (_, asset, node) = player()
    let report = try #require(node.events["media-tracks-report"]?.valueAction)
    let loading = Task { try await asset.loadMediaSelectionGroup(for: .legible) }
    await Task.yield()
    report(tracks)

    let legible = try #require(try await loading.value)
    #expect(legible.options.map(\.displayName) == ["Português", "English"])
    #expect(legible.options.first?.extendedLanguageTag == "pt")
    #expect(legible.allowsEmptySelection && legible.defaultOption == nil, "subtitles start off")
    let audible = try #require(try await asset.loadMediaSelectionGroup(for: .audible))
    #expect(audible.options.map(\.displayName) == ["Português", "en"], "a track without a label shows its language")
    #expect(audible.defaultOption?.displayName == "Português", "the one playing")
    let variants = try await asset.load(.variants)
    #expect(variants.compactMap { $0.videoAttributes?.presentationSize.height } == [1920, 1280])
    #expect(variants.first?.peakBitRate == 6_000_000)
  }

  @Test func a_cancelled_load_stops_waiting() async throws {
    let (_, asset, _) = player()
    let loading = Task { try await asset.loadMediaSelectionGroup(for: .legible) }
    await Task.yield()
    loading.cancel()
    #expect(try await loading.value == nil)
  }

  @Test func a_plain_file_has_no_alternatives() async throws {
    let (_, asset, node) = player()
    node.events["media-tracks-report"]?.valueAction?("")
    #expect(try await asset.loadMediaSelectionGroup(for: .legible) == nil)
    #expect(try await asset.load(.variants).isEmpty)
  }

  @Test func choices_render_for_the_host() async throws {
    let (player, asset, node) = player()
    node.events["media-tracks-report"]?.valueAction?(tracks)
    let item = try #require(player.currentItem)
    let legible = try #require(try await asset.loadMediaSelectionGroup(for: .legible))
    let audible = try #require(try await asset.loadMediaSelectionGroup(for: .audible))
    #expect(item.currentMediaSelection.selectedMediaOption(in: audible)?.displayName == "Português")

    item.preferredMaximumResolution = CGSize(width: 720, height: 1280)
    item.preferredPeakBitRate = 3_000_000
    item.select(legible.options[1], in: legible)
    item.select(audible.options[1], in: audible)
    var rendered = VideoPlayer(player: player)._render(in: _RenderContext())
    #expect(rendered.attributes["data-media-max-size"] == "720x1280")
    #expect(rendered.attributes["data-media-peak-bitrate"] == "3000000")
    #expect(rendered.attributes["data-media-text"] == "8")
    #expect(rendered.attributes["data-media-audio"] == "en/")
    #expect(item.currentMediaSelection.selectedMediaOption(in: legible)?.displayName == "English")

    item.select(nil, in: legible)
    item.select(nil, in: audible)
    rendered = VideoPlayer(player: player)._render(in: _RenderContext())
    #expect(rendered.attributes["data-media-text"] == "off")
    #expect(rendered.attributes["data-media-audio"] == "en/", "audio cannot be turned off")
    #expect(item.currentMediaSelection.selectedMediaOption(in: legible) == nil)

    item.preferredMaximumResolution = .zero
    #expect(VideoPlayer(player: player)._render(in: _RenderContext()).attributes["data-media-max-size"] == nil)
  }

  @Test func play_starts_at_the_default_rate() {
    let player = AVPlayer(url: URL(string: "https://media.example/pilot.mp4")!)
    player.defaultRate = 1.5
    player.play()
    #expect(player.rate == 1.5)
    #expect(VideoPlayer(player: player)._render(in: _RenderContext()).attributes["data-media-rate"] == "1.5")
    player.pause()
    player.defaultRate = 2
    player.play()
    #expect(player.rate == 2)
  }
}
