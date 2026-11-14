import Testing

/// `WebSecurity` holds one process-wide item store. Suites that install a store nest here, so they
/// run one at a time instead of replacing each other's store mid-test.
@Suite(.serialized)
enum GlobalKeychainSuites {}
