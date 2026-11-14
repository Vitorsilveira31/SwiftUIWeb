// The UTType stand-in is the Embedded/WASI subset. Natively UTType is Apple's (see SwiftUIWebUniformTypeIdentifiers),
// so these stand-in contracts are only compiled for Embedded/WASI builds.
import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebUniformTypeIdentifiers

@Suite
@MainActor
final class UniformTypeIdentifiersTests {
  @Test
  func testCommonTypesExposeCanonicalMetadata() {
    _expectEqual(UTType.data.identifier, "public.data")
    _expectEqual(UTType.plainText.identifier, "public.plain-text")
    _expectEqual(UTType.jpeg.identifier, "public.jpeg")
    _expectEqual(UTType.gif.identifier, "com.compuserve.gif")
    _expectEqual(UTType.pdf.identifier, "com.adobe.pdf")

    _expectEqual(UTType.plainText.preferredMIMEType, "text/plain")
    _expectEqual(UTType.html.preferredFilenameExtension, "html")
    _expectEqual(UTType.jpeg.preferredMIMEType, "image/jpeg")
    _expectEqual(UTType.jpeg.preferredFilenameExtension, "jpeg")
    _expectEqual(UTType.svg.preferredMIMEType, "image/svg+xml")
    _expectEqual(UTType.pdf.preferredFilenameExtension, "pdf")
  }

  @Test
  func testConformanceWalksTheTypeHierarchy() {
    _expectTrue(UTType.plainText.conforms(to: .text))
    _expectTrue(UTType.plainText.conforms(to: .data))
    _expectTrue(UTType.jpeg.conforms(to: .image))
    _expectTrue(UTType.jpeg.conforms(to: .data))
    _expectTrue(UTType.movie.conforms(to: .audiovisualContent))
    _expectTrue(UTType.movie.conforms(to: .video))
    _expectTrue(UTType.zip.conforms(to: .archive))
    _expectTrue(UTType.archive.conforms(to: .data))
    _expectFalse(UTType.jpeg.conforms(to: .audio))

    let exported = UTType(exportedAs: "com.example.thumbnail", conformingTo: .image)
    _expectTrue(exported.conforms(to: .image))
    _expectTrue(exported.conforms(to: .data))
    _expectTrue(exported.isDeclared)
    _expectFalse(exported.isDynamic)
    _expectEqual(exported, UTType("com.example.thumbnail"))
  }

  @Test
  func testMIMETypeResolutionIsCaseInsensitiveAndIgnoresParameters() {
    _expectEqual(UTType(mimeType: "IMAGE/JPEG"), .jpeg)
    _expectEqual(UTType(mimeType: "text/plain; charset=utf-8"), .plainText)
    _expectEqual(UTType(mimeType: "text/uri-list"), .url)
    _expectEqual(UTType(mimeType: "video/quicktime"), .movie)
    _expectEqual(UTType(mimeType: "application/zip"), .zip)
    _expectEqual(UTType(mimeType: "application/x-unknown"), nil)
    _expectNil(UTType(mimeType: ""))

    _expectEqual(
      UTType(tag: "image/png", tagClass: .MIMEType, conformingTo: .image),
      .png
    )
    _expectNil(UTType(tag: "application/pdf", tagClass: .MIMEType, conformingTo: .image))
  }

  @Test
  func testFilenameExtensionResolutionAcceptsDotsAndFilenames() {
    _expectEqual(UTType(filenameExtension: "PNG"), .png)
    _expectEqual(UTType(filenameExtension: ".jpg"), .jpeg)
    _expectEqual(UTType(filenameExtension: "photos/cover.jpeg"), .jpeg)
    _expectEqual(UTType(filenameExtension: "report.HTML"), .html)
    _expectEqual(UTType(filenameExtension: "movie.mp4"), .mpeg4Movie)
    _expectEqual(UTType(filenameExtension: "archive.tar.gz"), .gzip)
    _expectEqual(UTType(filenameExtension: "unknown"), nil)
    _expectNil(UTType(filenameExtension: ""))

    _expectEqual(
      UTType(tag: ".pdf", tagClass: .filenameExtension, conformingTo: .data),
      .pdf
    )
  }

  @Test
  func testCustomMetadataTagsAndIdentifierBasedIdentity() {
    let decorated = UTType(
      identifier: "org.example.custom",
      mimeType: "application/x-custom",
      filenameExtension: "custom"
    )
    let identifierOnly = UTType("org.example.custom")

    _expectEqual(decorated, identifierOnly)
    _expectEqual(Set([decorated, identifierOnly]).count, 1)
    _expectEqual(decorated.description, "org.example.custom")
    _expectTrue(decorated.conforms(to: identifierOnly))
    _expectTrue(decorated.isDynamic)
    _expectFalse(decorated.isPublic)
    _expectFalse(decorated.isReference)
    _expectEqual(decorated.preferredMIMEType, "application/x-custom")
    _expectEqual(decorated.preferredFilenameExtension, "custom")
    _expectEqual(decorated.filenameExtension, "custom")
    _expectEqual(decorated.tags[.MIMEType], ["application/x-custom"])
    _expectEqual(decorated.tags[.filenameExtension], ["custom"])

    let exportedRoot = UTType(exportedAs: "org.example.exported-root")
    let importedRoot = UTType(importedAs: "org.example.imported-root")
    _expectTrue(exportedRoot.isDeclared)
    _expectFalse(exportedRoot.isDynamic)
    _expectTrue(importedRoot.isDeclared)
    _expectFalse(importedRoot.isDynamic)
    _expectFalse(exportedRoot.conforms(to: .data))

    let jpegTags = UTType.jpeg.tags
    _expectEqual(jpegTags[.MIMEType], ["image/jpeg"])
    _expectEqual(jpegTags[.filenameExtension], ["jpeg", "jpg", "jpe"])

    let unknown = UTType("org.example.unknown")
    _expectNil(unknown.preferredMIMEType)
    _expectNil(unknown.preferredFilenameExtension)
    _expectTrue(unknown.tags.isEmpty)
    _expectFalse(unknown.isDeclared)
    _expectTrue(unknown.isDynamic)
    _expectFalse(unknown.isPublic)
    _expectFalse(unknown.conforms(to: .item))
  }

  @Test
  func testTagClassAndWhitespaceNormalizationFallbacks() {
    let unsupportedTagClass = UTTagClass(rawValue: "org.example.unsupported")
    _expectNil(UTType(tag: "image/png", tagClass: unsupportedTagClass))

    _expectEqual(UTType(mimeType: " \t IMAGE/JPEG \n; charset=utf-8"), .jpeg)
    _expectEqual(UTType(filenameExtension: "  photos/.PNG \t"), .png)
    _expectNil(UTType(filenameExtension: "folder/file."))

    // The movie type has two parent paths which converge at audiovisual-content.
    // Searching for an unrelated type exercises cycle/duplicate protection while
    // confirming that a miss does not imply conformance.
    _expectFalse(UTType.movie.conforms(to: .sourceCode))
  }
}
