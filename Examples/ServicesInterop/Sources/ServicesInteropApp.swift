import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebBrowserIO

@main
struct ServicesInteropApp: BrowserApp {
  var body: some View { WindowGroup { ServicesInteropView() } }
}

/// Calls the page's `echo` service (Resources/echo-service.js) and shows what comes back.
struct ServicesInteropView: View {
  @State private var greeting = "waiting"
  @State private var failure = "waiting"
  @State private var ticks: [String] = []
  @State private var observation: BrowserIOOperation?

  var body: some View {
    VStack(spacing: 12) {
      Text("greeting: \(greeting)")
      Text("failure: \(failure)")
      Text("ticks: \(ticks.joined(separator: ","))")
      Button("Start ticks") { BrowserService("echo").send("start") }
    }
    .task {
      observation = BrowserService("echo").observe("tick") { tick in ticks.append(tick) }
      do { greeting = try await BrowserService("echo").call("greet", "Swift") } catch { greeting = "error" }
      do {
        _ = try await BrowserService("echo").call("fail")
        failure = "none"
      } catch let error as BrowserIOError {
        failure = "code \(error.code)"
      } catch {
        failure = "other"
      }
    }
  }
}
