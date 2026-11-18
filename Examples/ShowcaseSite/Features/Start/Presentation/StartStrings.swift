/// The words of the getting-started page. The code is the same in both languages.
enum StartStrings {
  static func title(_ language: SiteLanguage) -> String {
    language.pick(pt: "Do zero ao primeiro app", en: "From zero to your first app")
  }

  static func lead(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "Três passos: um pacote Swift, um comando para rodar e uma pasta de arquivos estáticos para publicar.",
      en: "Three steps: a Swift package, one command to run it, and a folder of static files to ship."
    )
  }

  static func requirementsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "O que você precisa", en: "What you need")
  }

  static func requirements(_ language: SiteLanguage) -> [PurposeItemVO] {
    [
      PurposeItemVO(
        id: "swift",
        title: "Swift 6.4",
        detail: language.pick(
          pt: "A toolchain do swift.org, com o Swift SDK para WebAssembly da mesma versão. O compilador do Xcode não gera WebAssembly.",
          en: "The swift.org toolchain, with the Swift SDK for WebAssembly of the same release. Xcode's compiler does not build WebAssembly."
        ),
        symbol: "chevron.left.forwardslash.chevron.right"
      ),
      PurposeItemVO(
        id: "bun",
        title: "Bun",
        detail: language.pick(
          pt: "Roda os scripts de build e o servidor de desenvolvimento.",
          en: "Runs the build scripts and the development server."
        ),
        symbol: "shippingbox"
      ),
      PurposeItemVO(
        id: "os",
        title: "macOS 14+ / Linux",
        detail: language.pick(
          pt: "./swiftweb doctor lista tudo o que falta, com o comando que instala cada item.",
          en: "./swiftweb doctor lists everything missing, each with the command that installs it."
        ),
        symbol: "cpu"
      ),
    ]
  }

  static func stepsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Passo a passo", en: "Step by step")
  }

  static func steps(_ language: SiteLanguage) -> [StartStep] {
    [
      StartStep(
        id: "package",
        title: language.pick(pt: "1. Crie o pacote", en: "1. Create the package"),
        detail: language.pick(
          pt: "Um pacote Swift comum com um alvo executável. import SwiftUI compila contra o SwiftUIWeb, então as views ficam iguais às do iOS.",
          en: "An ordinary Swift package with an executable target. import SwiftUI compiles against SwiftUIWeb, so the views read as on iOS."
        ),
        code: packageManifest
      ),
      StartStep(
        id: "app",
        title: language.pick(pt: "2. Escreva o app", en: "2. Write the app"),
        detail: language.pick(
          pt: "Só o ponto de entrada é do navegador: BrowserApp. O resto é SwiftUI.",
          en: "Only the entry point is the browser's own: BrowserApp. The rest is SwiftUI."
        ),
        code: appSource
      ),
      StartStep(
        id: "run",
        title: language.pick(pt: "3. Rode", en: "3. Run it"),
        detail: language.pick(
          pt: "Compila, serve (o endereço aparece no terminal) e recarrega a página quando você salva.",
          en: "Builds, serves (the address is printed) and reloads the page when you save."
        ),
        code: runCommands
      ),
      StartStep(
        id: "ship",
        title: language.pick(pt: "4. Publique", en: "4. Ship it"),
        detail: language.pick(
          pt: "Gera uma pasta de arquivos estáticos para qualquer hospedagem estática.",
          en: "Writes a folder of static files for any static host."
        ),
        code: "./swiftweb build"
      ),
    ]
  }

  static func nextHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Para ir além", en: "Going further")
  }

  static func docLinks(_ language: SiteLanguage) -> [(title: String, path: String)] {
    [
      (language.pick(pt: "Guia completo", en: "Full quickstart"), "Documentation/QUICKSTART.md"),
      (language.pick(pt: "Publicar o app", en: "Deploying"), "Documentation/DEPLOYMENT.md"),
      (language.pick(pt: "Compartilhar código com um app Apple", en: "Sharing code with an Apple app"), "Documentation/SHARING_CODE.md"),
      (language.pick(pt: "Limitações", en: "Limitations"), "Documentation/LIMITATIONS.md"),
    ]
  }

  static let packageManifest = """
    // swift-tools-version: 6.4
    import PackageDescription

    let package = Package(
      name: "MyApp",
      dependencies: [
        .package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "\(SiteLinks.release)")
      ],
      targets: [
        .executableTarget(
          name: "MyApp",
          dependencies: [
            .product(name: "SwiftUIWeb", package: "swiftuiweb"),
            .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
          ],
          swiftSettings: [.unsafeFlags(["-module-alias", "SwiftUI=SwiftUIWeb"])]
        )
      ]
    )
    """

  static let appSource = """
    import SwiftUI
    import SwiftUIWebBrowser

    @main
    struct MyApp: BrowserApp {
      var body: some Scene {
        WindowGroup { Text("Hello, web").font(.largeTitle) }
      }
    }
    """

  static let runCommands = """
    swift package --allow-writing-to-package-directory web init   # once
    ./swiftweb dev
    """
}
