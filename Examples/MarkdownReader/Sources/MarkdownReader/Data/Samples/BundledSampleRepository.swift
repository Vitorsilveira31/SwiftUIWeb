/// The three documents compiled into the app.
struct BundledSampleRepository: SampleRepository {
    func source(for sample: Sample) -> String {
        switch sample {
        case .welcome: return WelcomeSampleText.source
        case .longDocument: return LongDocumentSampleText.source(sections: 300)
        case .tablesAndCode: return TablesAndCodeSampleText.source
        }
    }
}
