import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite(.serialized)
@MainActor
struct DeferredContentStateTests {
  private final class Submission {
    var value: String?
  }

  private struct FormFields: View {
    @Binding var email: String
    @Binding var password: String
    let submit: @MainActor () -> Void

    var body: some View {
      VStack {
        TextField("Email", text: $email)
        SecureField("Password", text: $password)
        Button("Submit", action: submit)
      }
    }
  }

  private struct Form: View {
    let submission: Submission
    @State(memberID: 101) private var email = ""
    @State(memberID: 102) private var password = ""

    var body: some View {
      GeometryReader { geometry in
        ScrollView {
          FormFields(email: $email, password: $password, submit: submit)
            .frame(minHeight: geometry.size.height)
        }
      }
    }

    private func submit() { submission.value = email + ":" + password }
  }

  enum Scope: CaseIterable { case optional, first, second, forEach }

  private struct Host: View {
    let scope: Scope
    let submission: Submission

    var body: some View {
      switch scope {
      case .optional:
        if true { Form(submission: submission) }
      case .first, .second:
        if scope == .first { Form(submission: submission) }
        else { Form(submission: submission) }
      case .forEach:
        ForEach(["row"], id: \.self) { _ in Form(submission: submission) }
      }
    }
  }

  @Test(arguments: Scope.allCases)
  func geometryMeasurementsPreserveControlIdentityAndBindings(scope: Scope) throws {
    let submission = Submission()
    let tree = FiberTree(Host(scope: scope, submission: submission))
    let initialEmail = try #require(find(in: tree.root) { $0.attributes["placeholder"] == "Email" })
    let initialID = initialEmail.structuralID
    tree.dispatch(event: "geometry", value: "800,600")
    _ = tree.renderNode
    let email = try #require(find(in: tree.root) { $0.attributes["placeholder"] == "Email" })
    #expect(email.structuralID == initialID)
    tree.dispatch(event: "input", value: "reader@example.test", at: email.identity)
    _ = tree.renderNode
    let password = try #require(find(in: tree.root) { $0.attributes["placeholder"] == "Password" })
    tree.dispatch(event: "input", value: "secret", at: password.identity)
    _ = tree.renderNode
    tree.dispatch(event: "geometry", value: "600,400")
    _ = tree.renderNode
    let resizedEmail = try #require(find(in: tree.root) { $0.attributes["placeholder"] == "Email" })
    #expect(resizedEmail.structuralID == initialID)
    tree.dispatch(event: "click")
    #expect(submission.value == "reader@example.test:secret")
    #expect(find(in: tree.root) { $0.attributes["placeholder"] == "Email" }?.renderNode.attributes["value"] == "reader@example.test")
  }

  private func find(in fiber: Fiber, matching: (_RenderNode) -> Bool) -> Fiber? {
    if matching(fiber.renderNode) { return fiber }
    for child in fiber.children {
      if let match = find(in: child, matching: matching) { return match }
    }
    return nil
  }
}
