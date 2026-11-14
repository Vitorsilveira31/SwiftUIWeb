import Testing
@testable import WebOSLog

/// OSLog's `Logger` in the browser (WebOSLog): what each message writes, and which values a release build hides.
struct WebOSLogTests {
  @Test
  func tagsTheLineWithTheSubsystemAndCategory() {
    #expect(Logger(subsystem: "com.example.app", category: "network").line("Started", redacting: false) == "[com.example.app:network] Started")
    #expect(Logger(subsystem: "", category: "network").line("Started", redacting: false) == "[network] Started")
    #expect(Logger().line("Started", redacting: false) == "Started")
  }

  @Test
  func showsEveryValueInADebugBuild() {
    let name = "Ana", count = 3
    let message: OSLogMessage = "\(name) has \(count) items, \(true), \(1.5), \(name, privacy: .private)"
    #expect(Logger().line(message, redacting: false) == "Ana has 3 items, true, 1.5, Ana")
  }

  /// Like Apple's unified logging without a debugger: `.auto` hides text but not numbers or Booleans, `.private` and
  /// `.sensitive` hide everything, `.public` nothing.
  @Test
  func hidesPrivateValuesInAReleaseBuild() {
    let name = "Ana", count = 3, token = 42
    let message: OSLogMessage =
      "\(name) has \(count) items (\(name, privacy: .public)), \(token, privacy: .private), \(name, privacy: .sensitive(mask: .hash)), \(false)"
    #expect(Logger().line(message, redacting: true) == "<private> has 3 items (Ana), <private>, <private>, false")
  }

  /// A Float is a number, so `.auto` shows it; the masked spellings of `.private` and `.auto` mean what the plain ones do.
  @Test
  func floatsAndMaskedPrivacyFollowTheirKind() {
    let ratio: Float = 0.5, name = "Ana"
    let message: OSLogMessage = "\(ratio) \(ratio, privacy: .private(mask: .hash)) \(name, privacy: .auto(mask: .none))"
    #expect(Logger().line(message, redacting: false) == "0.5 0.5 Ana")
    #expect(Logger().line(message, redacting: true) == "0.5 <private> <private>")
  }

  @Test
  func describesOtherValuesWithTheirDescription() {
    struct Order: CustomStringConvertible { var description: String { "order #7" } }
    #expect(Logger().line("Got \(Order(), privacy: .public)", redacting: true) == "Got order #7")
    #expect(Logger().line("Got \(Order())", redacting: true) == "Got <private>")
  }

  @Test
  func everyLevelWritesWithoutABrowserHost() {
    let logger = Logger(subsystem: "test", category: "levels")
    logger.log("log"); logger.log(level: .info, "info"); logger.trace("trace"); logger.debug("debug")
    logger.info("info"); logger.notice("notice"); logger.warning("warning"); logger.error("error")
    logger.critical("critical"); logger.fault("fault")
  }
}
