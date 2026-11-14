/// Supplies the Markdown source of each bundled sample.
protocol SampleRepository: Sendable {
    func source(for sample: Sample) -> String
}
