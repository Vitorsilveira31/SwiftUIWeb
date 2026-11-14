@_spi(Renderer) import SwiftUIWebTransferable

// SwiftUI's shader API. A shader is a Metal function compiled into the app's `.metallib`; a browser has no Metal, and
// no web API lets a shader read the pixels of the page's elements, so these effects draw the view unchanged. The types
// keep Apple's shape, so code that builds shaders compiles and runs.

/// A collection of shader functions: the app's default library, one from a bundle, data or a URL.
@dynamicMemberLookup public struct ShaderLibrary: Equatable, @unchecked Sendable {
  let identity: String

  /// The default library of the app's main bundle.
  public static let `default` = ShaderLibrary(identity: "default")

  public static func bundle(_ bundle: Bundle) -> ShaderLibrary { ShaderLibrary(identity: "bundle:" + (bundle.bundleIdentifier ?? "main")) }

  public init(data: Data) { identity = "data:" + String(data.count) }
  public init(url: URL) { identity = "url:" + url.absoluteString }
  init(identity: String) { self.identity = identity }

  /// The function `name` of the default library.
  public static subscript(dynamicMember name: String) -> ShaderFunction { ShaderFunction(library: .default, name: name) }
  /// The function `name` of this library.
  public subscript(dynamicMember name: String) -> ShaderFunction { ShaderFunction(library: self, name: name) }

  public static func == (lhs: ShaderLibrary, rhs: ShaderLibrary) -> Bool { lhs.identity == rhs.identity }
}

/// A function of a shader library; calling it with arguments makes a shader.
@dynamicCallable public struct ShaderFunction: Equatable, Sendable {
  public var library: ShaderLibrary
  public var name: String

  public init(library: ShaderLibrary, name: String) {
    self.library = library
    self.name = name
  }

  public func dynamicallyCall(withArguments args: [Shader.Argument]) -> Shader { Shader(function: self, arguments: args) }

  public static func == (a: ShaderFunction, b: ShaderFunction) -> Bool { a.library == b.library && a.name == b.name }
}

/// A shader function with the arguments it is called with.
public struct Shader: Equatable, Sendable {
  public typealias Resolved = Never

  /// An argument of a shader function.
  public struct Argument: Equatable, @unchecked Sendable {
    let description: String

    public static func float<T>(_ x: T) -> Shader.Argument where T: BinaryFloatingPoint { Argument(description: "float(\(Double(x)))") }
    public static func float2<T>(_ x: T, _ y: T) -> Shader.Argument where T: BinaryFloatingPoint {
      Argument(description: "float2(\(Double(x)),\(Double(y)))")
    }
    public static func float3<T>(_ x: T, _ y: T, _ z: T) -> Shader.Argument where T: BinaryFloatingPoint {
      Argument(description: "float3(\(Double(x)),\(Double(y)),\(Double(z)))")
    }
    public static func float4<T>(_ x: T, _ y: T, _ z: T, _ w: T) -> Shader.Argument where T: BinaryFloatingPoint {
      Argument(description: "float4(\(Double(x)),\(Double(y)),\(Double(z)),\(Double(w)))")
    }
    public static func float2(_ point: CGPoint) -> Shader.Argument { float2(point.x, point.y) }
    public static func float2(_ size: CGSize) -> Shader.Argument { float2(size.width, size.height) }
    public static func float2(_ vector: CGVector) -> Shader.Argument { float2(vector.dx, vector.dy) }
    public static func floatArray(_ array: [Float]) -> Shader.Argument { Argument(description: "floatArray(\(array.count))") }
    public static var boundingRect: Shader.Argument { Argument(description: "boundingRect") }
    public static func color(_ color: Color) -> Shader.Argument { Argument(description: "color(\(color.cssValue))") }
    public static func colorArray(_ array: [Color]) -> Shader.Argument { Argument(description: "colorArray(\(array.count))") }
    public static func image(_ image: Image) -> Shader.Argument { Argument(description: "image") }
    public static func data(_ data: Data) -> Shader.Argument { Argument(description: "data(\(data.count))") }

    public static func == (a: Shader.Argument, b: Shader.Argument) -> Bool { a.description == b.description }
  }

  /// How a shader is used, for `compile(as:)`.
  public struct UsageType: Hashable, Sendable {
    let rawValue: Int
    public static let shapeStyle = UsageType(rawValue: 0)
    public static let colorEffect = UsageType(rawValue: 1)
    public static let distortionEffect = UsageType(rawValue: 2)
    public static let layerEffect = UsageType(rawValue: 3)
  }

  public var function: ShaderFunction
  public var arguments: [Shader.Argument]
  public var dithersColor: Bool = false

  public init(function: ShaderFunction, arguments: [Shader.Argument]) {
    self.function = function
    self.arguments = arguments
  }

  /// Compiles the shader ahead of its first use. There is nothing to compile in a browser.
  public func compile(as type: Shader.UsageType) async throws {}

  public static func == (a: Shader, b: Shader) -> Bool {
    a.function == b.function && a.arguments == b.arguments && a.dithersColor == b.dithersColor
  }
}

public extension View {
  /// A Metal color shader over the view; a browser draws the view unchanged.
  nonisolated func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some View { modifier(_ShaderEffectModifier(kind: "color", shader: shader, isEnabled: isEnabled)) }
  /// A Metal distortion shader over the view; a browser draws the view unchanged.
  nonisolated func distortionEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View {
    modifier(_ShaderEffectModifier(kind: "distortion", shader: shader, isEnabled: isEnabled))
  }
  /// A Metal layer shader over the view; a browser draws the view unchanged.
  nonisolated func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View {
    modifier(_ShaderEffectModifier(kind: "layer", shader: shader, isEnabled: isEnabled))
  }
}

/// Records which shader would draw the view, for inspection; nothing in the page reads it.
nonisolated struct _ShaderEffectModifier: ViewModifier {
  let kind: String
  let shader: Shader
  let isEnabled: Bool
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard isEnabled else { return }
    node.attributes["data-shader-effect"] = kind + ":" + shader.function.name
  }
}
