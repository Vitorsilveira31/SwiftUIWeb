enum UVIndex {
    static func text(_ index: Double) -> String {
        let band = index < 3 ? Strings.UV.low
            : index < 6 ? Strings.UV.moderate
            : index < 8 ? Strings.UV.high
            : Strings.UV.veryHigh
        return Strings.UV.reading(Int(index.rounded()), band)
    }
}
