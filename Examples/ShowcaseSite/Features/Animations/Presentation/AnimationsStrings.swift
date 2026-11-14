/// The words of the animations page: its title, its opening line and, for each animation, a name, a sentence and the code.
enum AnimationsStrings {
  static func title(_ language: SiteLanguage) -> String {
    language.pick(pt: "Animações", en: "Animations")
  }

  static func lead(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "Cada cartão abaixo roda ao vivo e usa a API de animação do SwiftUI, com os mesmos nomes. O código de cada um abre no botão do cartão.",
      en: "Every card below runs live and uses SwiftUI's own animation API, under the same names. The code of each opens from the button on its card."
    )
  }

  static func codeLabel(_ language: SiteLanguage) -> String {
    language.pick(pt: "Código", en: "Code")
  }

  static func doneLabel(_ language: SiteLanguage) -> String {
    language.pick(pt: "Fechar", en: "Done")
  }

  static func all(_ language: SiteLanguage) -> [AnimationDemoVO] {
    [
      AnimationDemoVO(
        id: "numeric-text",
        title: language.pick(pt: "Números que rolam", en: "Numbers that roll"),
        detail: language.pick(
          pt: "contentTransition(.numericText): os dígitos giram até o novo valor, e só os que mudam se mexem.",
          en: "contentTransition(.numericText): the digits roll to the new value, and only the ones that change move."
        ),
        code: """
        @State private var count = 128

        Text("\\(count)")
          .font(.system(size: 56, weight: .bold, design: .rounded))
          .contentTransition(.numericText(value: Double(count)))
          .animation(.snappy, value: count)

        Button("+7") { count += 7 }
        """
      ),
      AnimationDemoVO(
        id: "transitions",
        title: language.pick(pt: "Transições", en: "Transitions"),
        detail: language.pick(
          pt: "Como uma view entra e sai: opacity, scale, slide, move e combinações com .combined(with:).",
          en: "How a view enters and leaves: opacity, scale, slide, move and combinations with .combined(with:)."
        ),
        code: """
        @State private var shown = true

        if shown {
          RoundedRectangle(cornerRadius: 14)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }

        Button("Hide") { withAnimation(.easeInOut(duration: 0.5)) { shown.toggle() } }
        """
      ),
      AnimationDemoVO(
        id: "curves",
        title: language.pick(pt: "Curvas e molas", en: "Curves and springs"),
        detail: language.pick(
          pt: "A mesma viagem com linear, easeInOut e uma mola .bouncy. A mola passa do ponto e volta.",
          en: "The same trip with linear, easeInOut and a .bouncy spring. The spring overshoots and settles."
        ),
        code: """
        @State private var arrived = false

        Circle()
          .offset(x: arrived ? 210 : 0)
          .animation(.bouncy(duration: 1.2), value: arrived)

        Button("Run") { arrived.toggle() }
        """
      ),
      AnimationDemoVO(
        id: "matched-geometry",
        title: language.pick(pt: "Mesma view, outro lugar", en: "Same view, new place"),
        detail: language.pick(
          pt: "matchedGeometryEffect: a pílula desliza para a aba escolhida em vez de sumir e reaparecer.",
          en: "matchedGeometryEffect: the pill slides to the chosen tab instead of disappearing and reappearing."
        ),
        code: """
        @Namespace private var tabs
        @State private var selected = 0

        ForEach(0..<3, id: \\.self) { index in
          Button(names[index]) { withAnimation(.snappy) { selected = index } }
            .matchedGeometryEffect(id: index, in: tabs)
        }
        .background {
          Capsule()
            .matchedGeometryEffect(id: selected, in: tabs, isSource: false)
        }
        """
      ),
      AnimationDemoVO(
        id: "phase",
        title: language.pick(pt: "Fases em loop", en: "Phases on a loop"),
        detail: language.pick(
          pt: "phaseAnimator percorre uma lista de fases, cada uma com a sua animação, e recomeça.",
          en: "phaseAnimator steps through a list of phases, each with its own animation, and starts over."
        ),
        code: """
        Image(systemName: "heart.fill")
          .phaseAnimator([1.0, 1.3, 1.0, 1.15]) { content, scale in
            content.scaleEffect(scale)
          } animation: { _ in
            .easeInOut(duration: 0.35)
          }
        """
      ),
      AnimationDemoVO(
        id: "keyframes",
        title: language.pick(pt: "Keyframes", en: "Keyframes"),
        detail: language.pick(
          pt: "keyframeAnimator: uma trilha por valor, com keyframes cúbicos, lineares e de mola, disparada a cada toque.",
          en: "keyframeAnimator: one track per value, with cubic, linear and spring keyframes, fired on each press."
        ),
        code: """
        struct JumpValues { var lift = 0.0; var stretch = 1.0 }

        Circle()
          .keyframeAnimator(initialValue: JumpValues(), trigger: jumps) { content, value in
            content.scaleEffect(x: 1 / value.stretch, y: value.stretch).offset(y: value.lift)
          } keyframes: { _ in
            KeyframeTrack(\\.lift) {
              CubicKeyframe(-48, duration: 0.3)
              CubicKeyframe(0, duration: 0.3)
            }
            KeyframeTrack(\\.stretch) {
              LinearKeyframe(1.25, duration: 0.15)
              LinearKeyframe(0.9, duration: 0.35)
              SpringKeyframe(1, duration: 0.3)
            }
          }
        """
      ),
      AnimationDemoVO(
        id: "symbol-effects",
        title: language.pick(pt: "Efeitos de símbolo", en: "Symbol effects"),
        detail: language.pick(
          pt: "symbolEffect faz o ícone pular, pulsar ou trocar por outro, como no SF Symbols.",
          en: "symbolEffect makes the icon bounce, pulse or swap for another, as SF Symbols do."
        ),
        code: """
        Image(systemName: "bell.fill").symbolEffect(.bounce, value: rings)
        Image(systemName: "wifi").symbolEffect(.pulse, isActive: listening)
        Image(systemName: starred ? "star.fill" : "star")
          .contentTransition(.symbolEffect(.replace))
        """
      ),
      AnimationDemoVO(
        id: "progress-ring",
        title: language.pick(pt: "Anel de progresso", en: "Progress ring"),
        detail: language.pick(
          pt: "Um círculo cortado com trim(from:to:) cresce com o valor, e o número ao lado rola junto.",
          en: "A circle cut with trim(from:to:) grows with the value, and the number beside it rolls along."
        ),
        code: """
        @State private var progress = 0.25

        Circle()
          .trim(from: 0, to: progress)
          .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text("\\(Int(progress * 100))%")
          .contentTransition(.numericText(value: progress))
          .animation(.easeInOut(duration: 0.9), value: progress)
        """
      ),
    ]
  }
}
