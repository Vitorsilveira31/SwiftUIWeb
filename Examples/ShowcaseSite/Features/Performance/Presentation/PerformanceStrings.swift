/// The words of the performance page. The numbers come from the measurements, never from here.
enum PerformanceStrings {
  static func title(_ language: SiteLanguage) -> String {
    language.pick(pt: "Desempenho contra o React", en: "Performance against React")
  }

  static func lead(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "O mesmo app escrito duas vezes, uma em SwiftUIWeb e outra em React, medido no mesmo navegador, na mesma máquina, passo a passo. Nenhum número desta página foi digitado à mão: eles saem do arquivo de resultados da medição.",
      en: "The same app written twice, once in SwiftUIWeb and once in React, measured in the same browser on the same machine, step by step. No number on this page was typed by hand: they come from the results file of the measurement."
    )
  }

  static func appHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "O app medido", en: "The app that was measured")
  }

  static func app(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "Uma lista de 2.000 obras com busca, favoritos, um painel de detalhe, um botão de adicionar, uma tela de estatísticas com 200 células e rolagem. É o tipo de tela de que uma ferramenta interna é feita, então os números dizem algo sobre esse tipo de trabalho e nada sobre outros.",
      en: "A list of 2,000 works with a search, favorites, a detail panel, an add button, a stats screen of 200 cells and scrolling. It is the kind of screen an internal tool is made of, so the numbers say something about that kind of work and nothing about others."
    )
  }

  static func resultsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Resultados", en: "Results")
  }

  static func networkHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Rede lenta: carga inicial", en: "Slow network: cold load")
  }

  /// The conditions of one network profile, with its numbers, and what the measurement covers.
  static func networkNote(_ network: PerformanceNetworkVO, _ language: SiteLanguage) -> String {
    language.pick(
      pt: "\(network.label): \(network.downloadMbps) Mbps de download, \(network.uploadKbps) kbps de upload e \(network.latency) ms de ida e volta, aplicados à página e aos seus workers. Só a carga inicial é medida, com a CPU na velocidade normal.",
      en: "\(network.label): \(network.downloadMbps) Mbps down, \(network.uploadKbps) kbps up and \(network.latency) ms round trip, applied to the page and its workers. Only the cold load is measured, with the CPU at its normal speed."
    )
  }

  static func cpuLabel(_ language: SiteLanguage) -> String {
    language.pick(pt: "CPU", en: "CPU")
  }

  static func cpuOption(_ rate: Int, _ language: SiteLanguage) -> String {
    rate == 1
      ? language.pick(pt: "Normal", en: "Normal")
      : language.pick(pt: "\(rate)x mais lenta", en: "\(rate)x slower")
  }

  static func summary(highest: Int, lowest: Int, same: Int, _ language: SiteLanguage) -> String {
    language.pick(
      pt: "Neste conjunto, o React levou mais que o SwiftUIWeb em \(highest) medidas, menos em \(lowest), e a diferença não foi relevante em \(same).",
      en: "In this set, React took more than SwiftUIWeb on \(highest) measures, less on \(lowest), and the difference was not significant on \(same)."
    )
  }

  static func swiftUIWebName(_ language: SiteLanguage, throttled: Bool = true) -> String {
    throttled ? "SwiftUIWeb" : language.pick(pt: "SwiftUIWeb (worker, sem limite de CPU)", en: "SwiftUIWeb (worker, not throttled)")
  }

  /// Where SwiftUIWeb's worker was not throttled, in place of React's verdict against it.
  static func notComparable(_ language: SiteLanguage) -> String {
    language.pick(pt: "Contra o SwiftUIWeb, não comparável: o worker não teve limite de CPU", en: "Against SwiftUIWeb, not comparable: its worker was not throttled")
  }

  static func mainThreadName(_ language: SiteLanguage) -> String {
    language.pick(pt: "Thread principal", en: "Main thread")
  }

  static func reactName(_ language: SiteLanguage) -> String { "React" }

  static func reactVirtualName(_ language: SiteLanguage) -> String {
    language.pick(pt: "React virtualizado", en: "React (virtualized)")
  }

  static func metric(_ id: String, _ language: SiteLanguage) -> String {
    switch id {
    case "load": return language.pick(pt: "Carga inicial, até o quadro na tela", en: "Cold load, to the board on screen")
    case "warmLoad": return language.pick(pt: "Carga com cache, até o quadro na tela", en: "Warm load, to the board on screen")
    case "lcp": return language.pick(pt: "Maior pintura de conteúdo (LCP), carga inicial", en: "Largest Contentful Paint, cold load")
    case "cls": return language.pick(pt: "Mudança de layout acumulada (CLS), vezes 1000", en: "Cumulative Layout Shift, times 1000")
    case "inp": return language.pick(pt: "Interação até o próximo quadro (INP), a mais lenta", en: "Interaction to Next Paint (INP), the slowest")
    case "transfer": return language.pick(pt: "Transferido para mostrar o quadro", en: "Transferred to show the board")
    case "nodes": return language.pick(pt: "Nós de DOM com o quadro na tela", en: "DOM nodes with the board on screen")
    case "type": return language.pick(pt: "Digitar na busca (mediana de 6 teclas)", en: "Typing in the search (median of 6 keys)")
    case "favorite": return language.pick(pt: "Marcar um favorito (mediana de 3)", en: "Marking a favorite (median of 3)")
    case "detail": return language.pick(pt: "Abrir uma obra (mediana de 3)", en: "Opening a work (median of 3)")
    case "add": return language.pick(pt: "Adicionar uma obra (mediana de 2)", en: "Adding a work (median of 2)")
    case "showStats": return language.pick(pt: "Trocar para as estatísticas (200 células)", en: "Switching to the stats (200 cells)")
    case "backToBoard": return language.pick(pt: "Voltar para o quadro", en: "Switching back to the board")
    case "scrollWorst": return language.pick(pt: "Rolar a lista, o quadro mais longo", en: "Scrolling the list, longest frame")
    case "scrollSlow": return language.pick(pt: "Rolar a lista, quadros acima de 25 ms (perdidos)", en: "Scrolling the list, frames over 25 ms (dropped)")
    case "blocking": return language.pick(pt: "Thread principal bloqueada (tarefas acima de 50 ms)", en: "Main thread blocked (tasks over 50 ms)")
    default: return work(id, language)
    }
  }

  /// The second reading of an interaction: when the DOM and its layout hold the change, before the frame that shows it.
  private static func work(_ id: String, _ language: SiteLanguage) -> String {
    switch id {
    case "loadWork": return language.pick(pt: "Carga inicial, até o DOM e o layout do quadro", en: "Cold load, to the DOM and layout of the board")
    case "warmLoadWork": return language.pick(pt: "Carga com cache, até o DOM e o layout do quadro", en: "Warm load, to the DOM and layout of the board")
    case "typeWork": return language.pick(pt: "Digitar na busca, até o DOM estar pronto", en: "Typing in the search, until the DOM is ready")
    case "favoriteWork": return language.pick(pt: "Marcar um favorito, até o DOM estar pronto", en: "Marking a favorite, until the DOM is ready")
    case "detailWork": return language.pick(pt: "Abrir uma obra, até o DOM estar pronto", en: "Opening a work, until the DOM is ready")
    case "addWork": return language.pick(pt: "Adicionar uma obra, até o DOM estar pronto", en: "Adding a work, until the DOM is ready")
    case "showStatsWork": return language.pick(pt: "Trocar para as estatísticas, até o DOM estar pronto", en: "Switching to the stats, until the DOM is ready")
    case "backToBoardWork": return language.pick(pt: "Voltar para o quadro, até o DOM estar pronto", en: "Switching back to the board, until the DOM is ready")
    default: return id
    }
  }

  /// A metric's number with its unit, to one decimal for times and sizes and whole for counts.
  static func value(_ value: Double, unit: String) -> String {
    let scaled = Int((value * 10).rounded())
    let text = unit.isEmpty ? "\(Int(value.rounded()))" : "\(scaled / 10).\(scaled % 10)"
    return unit.isEmpty ? text : "\(text) \(unit)"
  }

  static func verdict(_ verdict: PerformanceVerdict, percent: Int, _ language: SiteLanguage) -> String {
    let size = percent < 0 ? -percent : percent
    switch verdict {
    case .reactHigher: return language.pick(pt: "React: \(size)% a mais", en: "React: \(size)% more")
    case .reactLower: return language.pick(pt: "React: \(size)% a menos", en: "React: \(size)% less")
    case .same: return language.pick(pt: "Sem diferença relevante", en: "No significant difference")
    case .tooFewSamples: return language.pick(pt: "Poucas amostras", en: "Too few samples")
    }
  }

  /// The verdict against SwiftUIWeb with its Swift on the main thread.
  static func mainThreadVerdict(_ verdict: PerformanceVerdict, percent: Int, _ language: SiteLanguage) -> String {
    let size = percent < 0 ? -percent : percent
    switch verdict {
    case .reactHigher: return language.pick(pt: "Contra a thread principal, React: \(size)% a mais", en: "Against the main thread, React: \(size)% more")
    case .reactLower: return language.pick(pt: "Contra a thread principal, React: \(size)% a menos", en: "Against the main thread, React: \(size)% less")
    case .same: return language.pick(pt: "Contra a thread principal, sem diferença relevante", en: "Against the main thread, no significant difference")
    case .tooFewSamples: return language.pick(pt: "Contra a thread principal, poucas amostras", en: "Against the main thread, too few samples")
    }
  }

  /// The verdict of the virtualized React against SwiftUIWeb.
  static func virtualVerdict(_ verdict: PerformanceVerdict, percent: Int, _ language: SiteLanguage) -> String {
    let size = percent < 0 ? -percent : percent
    switch verdict {
    case .reactHigher: return language.pick(pt: "React virtualizado: \(size)% a mais", en: "Virtualized React: \(size)% more")
    case .reactLower: return language.pick(pt: "React virtualizado: \(size)% a menos", en: "Virtualized React: \(size)% less")
    case .same: return language.pick(pt: "React virtualizado: sem diferença relevante", en: "Virtualized React: no significant difference")
    case .tooFewSamples: return language.pick(pt: "React virtualizado: poucas amostras", en: "Virtualized React: too few samples")
    }
  }

  static func highlightsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Resumo", en: "At a glance")
  }

  static func highlightsLead(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "Seis medidas que contam a história. O que o SwiftUIWeb perde fica à vista, junto com o que ganha.",
      en: "Six measurements that tell the story. What SwiftUIWeb loses is shown next to what it wins."
    )
  }

  static func reactComparison(_ value: String, _ language: SiteLanguage) -> String {
    language.pick(pt: "React: \(value)", en: "React: \(value)")
  }

  /// Where SwiftUIWeb stands, from React's verdict (React higher means SwiftUIWeb is ahead).
  static func standing(_ verdict: PerformanceVerdict, _ language: SiteLanguage) -> String {
    switch verdict {
    case .reactHigher: return language.pick(pt: "À frente do React", en: "Ahead of React")
    case .reactLower: return language.pick(pt: "Atrás do React", en: "Behind React")
    case .same: return language.pick(pt: "Empatado", en: "On par")
    case .tooFewSamples: return language.pick(pt: "Poucas amostras", en: "Too few samples")
    }
  }

  static func slowLoadTitle(_ language: SiteLanguage) -> String {
    language.pick(pt: "Carga inicial em 4G lento", en: "Cold load on slow 4G")
  }

  static func expanded(_ language: SiteLanguage) -> String {
    language.pick(pt: "aberto", en: "expanded")
  }

  static func collapsed(_ language: SiteLanguage) -> String {
    language.pick(pt: "fechado", en: "collapsed")
  }

  static func allMeasurements(_ count: Int, _ language: SiteLanguage) -> String {
    language.pick(pt: "Todas as \(count) medições", en: "All \(count) measurements")
  }

  static func conditions(_ results: PerformanceResultsVO, _ language: SiteLanguage) -> String {
    language.pick(
      pt: "Medido em \(results.date), \(results.rounds) rodadas alternadas por métrica, \(results.browser), \(results.machine).",
      en: "Measured on \(results.date), \(results.rounds) alternating rounds per metric, \(results.browser), \(results.machine)."
    )
  }

  static func methodHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "Como foi medido", en: "How it was measured")
  }

  static func method(_ language: SiteLanguage) -> [PurposeItemVO] {
    [
      PurposeItemVO(
        id: "same",
        title: language.pick(pt: "O mesmo app, os mesmos dados", en: "The same app, the same data"),
        detail: language.pick(
          pt: "Os dois quadros mostram as mesmas 2.000 obras, geradas pelo mesmo algoritmo, e um teste confere que respondem igual a cada busca antes de qualquer medição.",
          en: "Both boards show the same 2,000 works, made by the same algorithm, and a test checks that they answer every search alike before anything is measured."
        )
      ),
      PurposeItemVO(
        id: "rounds",
        title: language.pick(pt: "Rodadas alternadas", en: "Alternating rounds"),
        detail: language.pick(
          pt: "Cada rodada roda o roteiro uma vez de cada lado, variando quem vai primeiro, em um navegador novo. O que a máquina estava fazendo naquele instante vale para os dois lados.",
          en: "Each round runs the script once on each side, varying who goes first, in a fresh browser. What the machine was doing at that moment is shared by both sides."
        )
      ),
      PurposeItemVO(
        id: "number",
        title: language.pick(pt: "Dois tempos por interação", en: "Two readings per interaction"),
        detail: language.pick(
          pt: "Um vai do evento de entrada até o quadro que mostra o resultado na tela. O outro, \"até o DOM estar pronto\", vai até o DOM e o layout terem a mudança, antes desse quadro. Os dois são lidos da própria página, do mesmo jeito nos dois lados.",
          en: "One runs from the input event to the frame that shows the result on screen. The other, \"until the DOM is ready\", runs until the DOM and its layout hold the change, before that frame. Both are read from the page itself, the same way on both sides."
        )
      ),
      PurposeItemVO(
        id: "stats",
        title: language.pick(pt: "Só conta o que supera o ruído", en: "Only what beats the noise counts"),
        detail: language.pick(
          pt: "Uma diferença só é dita quando o intervalo de confiança exclui zero, p é menor que 0,01 e a mudança é de pelo menos 5%. O resto é \"sem diferença relevante\".",
          en: "A difference is reported only when the confidence interval excludes zero, p is below 0.01 and the change is at least 5 percent. Everything else reads \"no significant difference\"."
        )
      ),
    ]
  }

  static func caveatsHeading(_ language: SiteLanguage) -> String {
    language.pick(pt: "O que isso não diz", en: "What this does not say")
  }

  static func caveats(_ language: SiteLanguage) -> [PurposeItemVO] {
    [
      PurposeItemVO(
        id: "list",
        title: language.pick(pt: "O React comum não virtualiza a lista", en: "Plain React does not virtualize its list"),
        detail: language.pick(
          pt: "Ele renderiza todas as obras, cada uma em React.memo, como se escreve uma lista longa. A barra \"React virtualizado\" é o mesmo quadro com só as linhas à vista (e uma margem de 20) no DOM, escrito à mão e sem biblioteca. O SwiftUIWeb monta só as linhas à vista, como ela.",
          en: "It renders every work, each in React.memo, the way a long list is written. The \"React (virtualized)\" bar is the same board with only the rows in view (and a margin of 20) in the DOM, written by hand without a library. SwiftUIWeb builds only the rows in view, as it does."
        )
      ),
      PurposeItemVO(
        id: "worker",
        title: language.pick(pt: "O SwiftUIWeb roda em um Worker", en: "SwiftUIWeb runs in a Worker"),
        detail: language.pick(
          pt: "Por padrão o Swift roda em um Web Worker e o DOM é publicado no próximo quadro de animação, o que soma cerca de um quadro até a tela. Por isso há uma terceira barra: o mesmo pacote com o Swift na thread principal. Cada uma é comparada com o React, nunca entre si. O Chromium não aplica limite de CPU a um worker: nas medidas de CPU 4x, a barra do SwiftUIWeb (worker) roda na velocidade real e não é comparada com o React. A barra da thread principal é a limitada.",
          en: "By default the Swift runs in a Web Worker and the DOM is published in the next animation frame, which adds about one frame until the screen. That is why there is a third bar: the same bundle with the Swift on the main thread. Each is compared with React, never with the other. Chromium does not apply a CPU limit to a worker: in the CPU 4x measures the SwiftUIWeb (worker) bar runs at full speed and is not compared with React. The main-thread bar is the one that is throttled."
        )
      ),
      PurposeItemVO(
        id: "scope",
        title: language.pick(pt: "Um app, uma máquina, um navegador", en: "One app, one machine, one browser"),
        detail: language.pick(
          pt: "Fora a medida de rede lenta, que é só da carga inicial, a rede é local. O navegador é o Chromium e a tela é uma só. Leia a direção de cada diferença como o achado e o tamanho dela como um exemplo.",
          en: "Apart from the slow network measure, which is the cold load only, the network is local. The browser is Chromium and the screen is one. Read the direction of each difference as the finding and its size as an example."
        )
      ),
      PurposeItemVO(
        id: "reproduce",
        title: language.pick(pt: "Dá para refazer", en: "You can run it again"),
        detail: language.pick(
          pt: "O app em React, o app em SwiftUIWeb, o roteiro e o executor estão no repositório (Benchmarks/ReactComparison), com os comandos no README.",
          en: "The React app, the SwiftUIWeb app, the script and the runner are in the repository (Benchmarks/ReactComparison), with the commands in its README."
        )
      ),
    ]
  }
}
