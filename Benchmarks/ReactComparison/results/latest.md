CPU 1x

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 51.4 ms (±3.4) | 50.2 ms (±0.5) | 36.1 ms (±3.1) | 33.5 ms (±3.3) | -32% (React lower) | -32% (React lower) | -33% (React lower) |
| Cold load, to the DOM and layout of the board | 59.4 ms (±0.5) | 52.6 ms (±0.9) | 41.4 ms (±0.6) | 17.8 ms (±0.3) | -31% (React lower) | -21% (React lower) | -70% (React lower) |
| Warm load, to the board on screen | 47.4 ms (±1.1) | 30.4 ms (±0.9) | 30.4 ms (±1.2) | 30.2 ms (±0.9) | -35% (React lower) | +0% (no significant difference) | -35% (React lower) |
| Warm load, to the DOM and layout of the board | 22.2 ms (±0.4) | 21.9 ms (±0.6) | 26.0 ms (±0.4) | 7.0 ms (±0.2) | +17% (React higher) | +18% (React higher) | -69% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 68.0 ms (±0.0) | 60.0 ms (±4.0) | 52.0 ms (±0.0) | 40.0 ms (±0.0) | -24% (React lower) | -13% (React lower) | -41% (React lower) |
| Transferred to show the board | 552.3 KB (±0.0) | 529.1 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -90% (React lower) | -89% (React lower) | -90% (React lower) |
| DOM nodes with the board on screen | 303.0 (±0.0) | 303.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2549% (React higher) | +2549% (React higher) | -35% (React lower) |
| Typing in the search (median of 6 keys) | 30.2 ms (±0.8) | 29.8 ms (±0.9) | 30.4 ms (±0.4) | 30.5 ms (±0.3) | +2% (no significant difference) | +3% (no significant difference) | +1% (no significant difference) |
| Typing in the search, until the DOM is ready | 10.2 ms (±0.2) | 19.2 ms (±0.6) | 3.7 ms (±0.1) | 1.3 ms (±0.1) | -63% (React lower) | -81% (React lower) | -86% (React lower) |
| Marking a favorite (median of 3) | 30.5 ms (±0.9) | 30.5 ms (±1.0) | 30.2 ms (±0.5) | 30.6 ms (±0.8) | -0% (no significant difference) | -0% (no significant difference) | +1% (no significant difference) |
| Marking a favorite, until the DOM is ready | 3.7 ms (±0.2) | 20.2 ms (±0.3) | 2.0 ms (±0.2) | 0.8 ms (±0.1) | -43% (React lower) | -90% (React lower) | -78% (React lower) |
| Opening a work (median of 3) | 30.5 ms (±0.7) | 30.8 ms (±1.4) | 30.2 ms (±0.8) | 30.6 ms (±0.8) | -1% (no significant difference) | -1% (no significant difference) | +0% (no significant difference) |
| Opening a work, until the DOM is ready | 3.6 ms (±0.1) | 21.3 ms (±0.8) | 2.6 ms (±0.2) | 0.6 ms (±0.1) | -28% (React lower) | -88% (React lower) | -81% (React lower) |
| Adding a work (median of 2) | 30.6 ms (±0.8) | 30.9 ms (±1.2) | 30.5 ms (±0.6) | 30.5 ms (±0.5) | +1% (no significant difference) | -0% (no significant difference) | -0% (no significant difference) |
| Adding a work, until the DOM is ready | 7.0 ms (±0.1) | 18.8 ms (±0.5) | 2.3 ms (±0.1) | 0.7 ms (±0.0) | -66% (React lower) | -87% (React lower) | -90% (React lower) |
| Switching to the stats (200 cells) | 30.6 ms (±0.9) | 31.0 ms (±1.2) | 30.6 ms (±0.5) | 30.8 ms (±0.7) | -0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Switching to the stats, until the DOM is ready | 17.5 ms (±0.3) | 25.2 ms (±1.8) | 5.0 ms (±0.2) | 1.5 ms (±0.1) | -71% (React lower) | -80% (React lower) | -91% (React lower) |
| Switching back to the board | 30.6 ms (±0.9) | 30.7 ms (±1.4) | 30.7 ms (±0.7) | 30.5 ms (±0.5) | -1% (no significant difference) | +1% (no significant difference) | -0% (no significant difference) |
| Switching back to the board, until the DOM is ready | 10.1 ms (±0.4) | 20.8 ms (±0.3) | 19.4 ms (±0.3) | 1.4 ms (±0.2) | +92% (React higher) | -6% (React lower) | -86% (React lower) |
| Scrolling the list, longest frame | 16.8 ms (±0.0) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 32.0 ms (±8.0) | 40.0 ms (±0.0) | 40.0 ms (±0.0) | 40.0 ms (±0.0) | +25% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |

CPU 4x

SwiftUIWeb (worker) is not throttled: the throttle reached the page only: Chromium refuses the throttle for a worker. Its numbers are not a 4x CPU and are not compared with React.

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 135.6 ms (±9.9), not throttled | 210.8 ms (±9.6) | 171.5 ms (±8.0) | 57.1 ms (±9.1) | not comparable | -19% (React lower) | not comparable |
| Cold load, to the DOM and layout of the board | 135.5 ms (±2.9), not throttled | 205.5 ms (±4.4) | 164.1 ms (±3.4) | 64.1 ms (±1.5) | not comparable | -20% (React lower) | not comparable |
| Warm load, to the board on screen | 63.2 ms (±1.0), not throttled | 96.4 ms (±0.8) | 113.3 ms (±1.0) | 29.1 ms (±1.8) | not comparable | +17% (React higher) | not comparable |
| Warm load, to the DOM and layout of the board | 61.1 ms (±1.4), not throttled | 95.1 ms (±3.0) | 107.4 ms (±1.4) | 25.7 ms (±0.8) | not comparable | +13% (React higher) | not comparable |
| Largest Contentful Paint, cold load (Chromium) | 148.0 ms (±4.0), not throttled | 228.0 ms (±4.0) | 188.0 ms (±6.0) | 76.0 ms (±0.0) | not comparable | -18% (React lower) | not comparable |
| Transferred to show the board | 552.3 KB (±0.0), not throttled | 137.5 KB (±391.6) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | not comparable | -58% (React lower) | not comparable |
| DOM nodes with the board on screen | 303.0 (±0.0), not throttled | 303.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | not comparable | +2549% (React higher) | not comparable |
| Typing in the search (median of 6 keys) | 27.0 ms (±0.7), not throttled | 37.9 ms (±3.5) | 31.0 ms (±0.5) | 30.0 ms (±0.9) | not comparable | -19% (React lower) | not comparable |
| Typing in the search, until the DOM is ready | 19.6 ms (±0.8), not throttled | 44.7 ms (±1.1) | 17.1 ms (±0.7) | 5.7 ms (±0.5) | not comparable | -62% (React lower) | not comparable |
| Marking a favorite (median of 3) | 27.6 ms (±0.9), not throttled | 28.6 ms (±1.6) | 27.9 ms (±0.9) | 28.7 ms (±1.0) | not comparable | -3% (no significant difference) | not comparable |
| Marking a favorite, until the DOM is ready | 9.4 ms (±0.3), not throttled | 35.9 ms (±1.2) | 10.2 ms (±0.9) | 3.7 ms (±0.5) | not comparable | -72% (React lower) | not comparable |
| Opening a work (median of 3) | 28.1 ms (±0.8), not throttled | 28.4 ms (±0.9) | 27.6 ms (±0.9) | 29.0 ms (±0.3) | not comparable | -1% (no significant difference) | not comparable |
| Opening a work, until the DOM is ready | 7.8 ms (±0.5), not throttled | 36.7 ms (±2.2) | 12.3 ms (±0.4) | 3.1 ms (±0.3) | not comparable | -66% (React lower) | not comparable |
| Adding a work (median of 2) | 28.5 ms (±1.2), not throttled | 27.9 ms (±1.1) | 29.0 ms (±0.8) | 28.7 ms (±0.5) | not comparable | +3% (no significant difference) | not comparable |
| Adding a work, until the DOM is ready | 16.2 ms (±0.8), not throttled | 29.7 ms (±1.2) | 10.4 ms (±0.7) | 3.5 ms (±0.3) | not comparable | -65% (React lower) | not comparable |
| Switching to the stats (200 cells) | 44.9 ms (±1.2), not throttled | 78.1 ms (±16.9) | 29.3 ms (±0.9) | 29.2 ms (±1.4) | not comparable | -62% (React lower) | not comparable |
| Switching to the stats, until the DOM is ready | 36.1 ms (±0.9), not throttled | 79.2 ms (±5.7) | 21.8 ms (±0.7) | 7.1 ms (±0.5) | not comparable | -73% (React lower) | not comparable |
| Switching back to the board | 27.1 ms (±0.9), not throttled | 45.3 ms (±1.5) | 95.4 ms (±1.6) | 29.1 ms (±0.9) | not comparable | +111% (React higher) | not comparable |
| Switching back to the board, until the DOM is ready | 21.4 ms (±0.6), not throttled | 46.1 ms (±1.9) | 84.9 ms (±3.1) | 6.0 ms (±0.4) | not comparable | +81% (React higher) | not comparable |
| Scrolling the list, longest frame | 16.8 ms (±0.0), not throttled | 33.4 ms (±0.1) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | not comparable | -50% (React lower) | not comparable |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0), not throttled | 3.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.2 (±0.2), not throttled | 0.2 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 48.0 ms (±12.0), not throttled | 88.0 ms (±8.0) | 104.0 ms (±8.0) | 48.0 ms (±4.0) | not comparable | +18% (React higher) | not comparable |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0), not throttled | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | not comparable | +0% (no significant difference) | not comparable |

Slow 4G (cold load, 15 rounds)

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 3095.9 ms (±5.9) | 3086.3 ms (±7.1) | 644.4 ms (±9.1) | 640.0 ms (±9.4) | -79% (React lower) | -79% (React lower) | -79% (React lower) |
| Cold load, to the DOM and layout of the board | 3096.0 ms (±7.3) | 3088.3 ms (±4.4) | 645.6 ms (±7.1) | 620.6 ms (±1.0) | -79% (React lower) | -79% (React lower) | -80% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 3104.0 ms (±8.0) | 3096.0 ms (±6.0) | 656.0 ms (±8.0) | 632.0 ms (±12.0) | -79% (React lower) | -79% (React lower) | -80% (React lower) |
| Transferred to show the board | 552.3 KB (±0.0) | 529.1 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -90% (React lower) | -89% (React lower) | -90% (React lower) |
| DOM nodes with the board on screen | 303.0 (±0.0) | 303.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2549% (React higher) | +2549% (React higher) | -35% (React lower) |
