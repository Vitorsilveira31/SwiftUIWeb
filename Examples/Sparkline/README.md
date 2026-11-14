# Sparkline

A market list: forty coins, each row with a name, a 48-point sparkline that draws in on appear, a price and a
change pill. A Tick button moves every third series on, Freeze stops the pulse rings. It presses on `List` with
plain row styling, `Shape` with `trim` and `stroke`, `TimelineView(.animation(paused:))` for the pulse, `NavigationStack`
with a toolbar `ToolbarItemGroup`, and `@Observable` state with `@State` in the view.

```
Sources/Sparkline/
  App/SparklineRootView.swift              NavigationStack and the "Markets" title
  Core/Strings.swift                       user-visible text
  Data/CoinVO.swift                        one row's values
  Data/CoinRepository.swift                protocol the screen depends on
  Data/SampleCoinRepository.swift          deterministic sample series
  Data/CoinRandom.swift                    seeded generator, same rows on every host
  Features/Markets/MarketsViewModel.swift  state and actions (tick, toggleFreeze)
  Features/Markets/Views/                  list, row, badge, title, price, pill, chart, pulse, line shape
```

Run on iOS: open `Darwin/Sparkline.xcodeproj` and pick the scheme "Sparkline App".
Run in the browser: `make example-web EXAMPLE=Sparkline` from the repository root.
