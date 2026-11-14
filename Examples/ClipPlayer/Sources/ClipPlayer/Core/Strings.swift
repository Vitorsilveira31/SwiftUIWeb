/// Every user-visible text of the app.
enum Strings {
    static let title = "Video"

    enum Player {
        static let clipPicker = "Video"
        static let clipsHeading = "Clips"
        static func videoLabel(_ clipTitle: String) -> String { "Video: \(clipTitle)" }

        static let rewind = "Rewind to the start"
        static let back = "Back 10 seconds"
        static let forward = "Forward 10 seconds"
        static let play = "Play"
        static let pause = "Pause"

        static let playbackPosition = "Playback position"
        static let playbackSpeed = "Playback speed"
        static let halfSpeed = "0.5x"
        static let normalSpeed = "1x"
        static let oneAndHalfSpeed = "1.5x"
        static let doubleSpeed = "2x"
        static let mute = "Mute"
        static let volume = "Volume"

        static let noteHeading = "Keep watching. Leave a thought."
        static let notePlaceholder = "Tap here to bring up the keyboard"
        static let noteLabel = "Your note"
        static let done = "Done"

        static let loadFailed = "The video could not be loaded."
        static let stoppedPlaying = "The video stopped playing."
    }
}
