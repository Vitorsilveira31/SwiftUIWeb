import Testing
@_spi(Renderer) @testable import SwiftUIWebCore

/// `WebElementHandle.setAttribute` and media sources keep ordinary values but never become script.
@Suite
struct MountedAttributeTests {
  @Test
  func mountedAttributesRefuseScriptOnly() {
    #expect(_safeMountedAttributeValue(name: "data-demo-token", value: "abc") == "abc")
    #expect(_safeMountedAttributeValue(name: "aria-label", value: "Play") == "Play")
    #expect(_safeMountedAttributeValue(name: "src", value: "blob:https://app.example.test/1") == "blob:https://app.example.test/1")
    #expect(_safeMountedAttributeValue(name: "src", value: "media/a.mp4") == "media/a.mp4")
    #expect(_safeMountedAttributeValue(name: "onclick", value: "alert(1)") == nil)
    #expect(_safeMountedAttributeValue(name: "ONLOAD", value: "x") == nil)
    #expect(_safeMountedAttributeValue(name: "srcdoc", value: "<script>x</script>") == nil)
    #expect(_safeMountedAttributeValue(name: "href", value: "java\tscript:alert(1)") == nil)
    #expect(_isSafeMountedURL("https://cdn.example.test/a.m3u8"))
    #expect(!_isSafeMountedURL("javascript:alert(1)"))
    // Markup: an image or video source may be data: or blob:, a link may not.
    #expect(_safeAttributeValue(name: "src", value: "data:image/png;base64,AAAA") == "data:image/png;base64,AAAA")
    #expect(_safeAttributeValue(name: "poster", value: "blob:https://app.example.test/1") != nil)
    #expect(_safeAttributeValue(name: "href", value: "data:text/html,x") == nil)
    #expect(_safeAttributeValue(name: "src", value: "javascript:alert(1)") == nil)
  }
}
