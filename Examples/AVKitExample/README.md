# AVKitExample

Three video players from `SwiftUIWebAVKit`, one for each kind of source: an MP4 file, an HLS playlist and a DASH manifest. The
browser plays the MP4 and HLS sources natively, or through a fallback when the browser cannot. The DASH manifest is played by
Shaka Player, which is fetched only when that player is rendered.

```sh
make run avkit                # build and serve it (it prints the address)
make list                     # the other examples
```

The page has three `VideoPlayer` views, each with its own `AVPlayer`, and three buttons that drive the first one: Play MP4, Pause
MP4 and Seek 30s. The sources are public test streams (an MDN sample, a Mux test stream and a Shaka demo asset), so the page needs
network access to play them.

What to look at in `main.swift`:

- The three `AVPlayer` values, with one URL each. Only the MP4 and HLS sources play with the browser's own media element; the last
  one is the adaptive case.
- `VideoPlayer(player:)`, the view that the app mounts for each player.
- `Self.mp4.play()`, `pause()` and `seek(to:)`: the `AVPlayer`-shaped calls that the framework maps to the media element.

The same behavior is covered by the controls suite in `Tools/test-avkit-controls-browser.mjs`.
