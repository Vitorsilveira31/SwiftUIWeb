# MediaExample

Playback with the `SwiftUIWebAVFoundation` and `SwiftUIWebAVKit` API shape: an `AVPlayer` drives the browser's own HTML media element,
for a video and for an audio file. The Swift code does not import any browser or DOM type, so the same calls work in ordinary Swift
code.

```sh
make run media                # build and serve it (it prints the address)
make media-worker-test        # the media worker suite
```

The page shows the video with Play, Pause and Seek 30s buttons and its duration, and a second `VideoPlayer` for an audio file below it.
The sources are public sample files from MDN, so the page needs network access to load them.

What to look at in `main.swift`:

- `AVPlayer(url:)` for each source. The player is a static value, so the buttons can call it directly.
- `VideoPlayer(player:)` for the picture and the controls, and a second one for audio.
- `Self.player.currentItem?.duration.seconds`, read to show the duration once the media has loaded.
- `CMTime(seconds:preferredTimescale:)`, used for the seek.
