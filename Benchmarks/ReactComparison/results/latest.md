CPU 1x

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 107.9 ms (±44.4) | 104.5 ms (±16.4) | 77.1 ms (±25.6) | 46.2 ms (±10.3) | -36% (React lower) | -23% (no significant difference) | -56% (React lower) |
| Cold load, to the DOM and layout of the board | 111.6 ms (±41.9) | 106.4 ms (±16.8) | 82.0 ms (±17.0) | 36.5 ms (±8.9) | -32% (React lower) | -23% (React lower) | -69% (React lower) |
| Warm load, to the board on screen | 47.3 ms (±12.7) | 46.8 ms (±0.7) | 46.8 ms (±1.7) | 30.5 ms (±0.7) | -2% (no significant difference) | -0% (no significant difference) | -36% (React lower) |
| Warm load, to the DOM and layout of the board | 52.7 ms (±21.4) | 45.7 ms (±7.8) | 51.7 ms (±8.3) | 12.8 ms (±2.6) | -4% (no significant difference) | +6% (no significant difference) | -71% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 124.0 ms (±44.0) | 120.0 ms (±20.0) | 100.0 ms (±22.0) | 56.0 ms (±12.0) | -23% (React lower) | -20% (React lower) | -58% (React lower) |
| Transferred to show the board | 285.7 KB (±0.0) | 400.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -80% (React lower) | -86% (React lower) | -80% (React lower) |
| DOM nodes with the board on screen | 304.0 (±0.0) | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2540% (React higher) | +2540% (React higher) | -36% (React lower) |
| Typing in the search (median of 6 keys) | 30.3 ms (±15.6) | 29.7 ms (±1.0) | 30.7 ms (±0.9) | 30.6 ms (±0.5) | -5% (no significant difference) | +3% (no significant difference) | -1% (no significant difference) |
| Typing in the search, until the DOM is ready | 21.0 ms (±3.9) | 22.3 ms (±1.9) | 7.0 ms (±0.9) | 2.3 ms (±0.2) | -68% (React lower) | -69% (React lower) | -90% (React lower) |
| Marking a favorite (median of 3) | 30.2 ms (±0.9) | 30.1 ms (±0.8) | 30.2 ms (±0.4) | 30.4 ms (±0.7) | -0% (no significant difference) | +1% (no significant difference) | +1% (no significant difference) |
| Marking a favorite, until the DOM is ready | 6.3 ms (±1.6) | 23.2 ms (±1.5) | 3.5 ms (±0.3) | 1.4 ms (±0.1) | -46% (React lower) | -83% (React lower) | -78% (React lower) |
| Opening a work (median of 3) | 30.6 ms (±0.7) | 30.2 ms (±0.7) | 30.0 ms (±0.8) | 30.4 ms (±0.8) | -1% (no significant difference) | -0% (no significant difference) | +1% (no significant difference) |
| Opening a work, until the DOM is ready | 6.0 ms (±1.0) | 23.5 ms (±2.0) | 4.7 ms (±0.4) | 1.1 ms (±0.1) | -22% (no significant difference) | -80% (React lower) | -80% (React lower) |
| Adding a work (median of 2) | 30.5 ms (±1.0) | 30.2 ms (±0.4) | 30.3 ms (±1.0) | 30.4 ms (±0.7) | +0% (no significant difference) | +0% (no significant difference) | +1% (no significant difference) |
| Adding a work, until the DOM is ready | 11.5 ms (±2.7) | 20.4 ms (±1.2) | 3.7 ms (±0.1) | 1.2 ms (±0.1) | -69% (React lower) | -82% (React lower) | -90% (React lower) |
| Switching to the stats (200 cells) | 46.9 ms (±1.5) | 30.6 ms (±0.8) | 30.7 ms (±0.5) | 30.7 ms (±0.6) | -34% (React lower) | +1% (no significant difference) | -35% (React lower) |
| Switching to the stats, until the DOM is ready | 31.3 ms (±9.4) | 34.6 ms (±4.0) | 9.0 ms (±0.9) | 2.8 ms (±0.3) | -73% (React lower) | -73% (React lower) | -91% (React lower) |
| Switching back to the board | 30.6 ms (±1.0) | 30.7 ms (±1.0) | 30.7 ms (±0.7) | 30.5 ms (±1.1) | +2% (no significant difference) | +1% (no significant difference) | -1% (no significant difference) |
| Switching back to the board, until the DOM is ready | 20.0 ms (±4.5) | 23.7 ms (±1.3) | 38.0 ms (±4.9) | 2.4 ms (±0.2) | +74% (React higher) | +59% (React higher) | -88% (React lower) |
| Scrolling the list, longest frame | 16.8 ms (±0.0) | 33.3 ms (±16.5) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | +0% (no significant difference) | -50% (no significant difference) | +0% (no significant difference) |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0) | 1.0 (±1.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | -100% (no significant difference) | +0% (no significant difference) |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.0 (±0.2) | 0.0 (±0.1) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 48.0 ms (±12.0) | 72.0 ms (±12.0) | 64.0 ms (±8.0) | 56.0 ms (±8.0) | +17% (React higher) | -11% (no significant difference) | +17% (no significant difference) |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) | 

CPU 4x: round 1/15CPU 4x: round 2/15CPU 4x: round 3/15CPU 4x: round 4/15CPU 4x: round 5/15CPU 4x: round 6/15CPU 4x: round 7/15CPU 4x: round 8/15CPU 4x: round 9/15CPU 4x: round 10/15CPU 4x: round 11/15CPU 4x: round 12/15CPU 4x: round 13/15CPU 4x: round 14/15CPU 4x: round 15/15
CPU 4x

SwiftUIWeb (worker) is not throttled: the throttle reached the page only: Chromium refuses the throttle for a worker. Its numbers are not a 4x CPU and are not compared with React.

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 236.2 ms (±93.2), not throttled | 335.1 ms (±72.7) | 235.1 ms (±58.7) | 84.0 ms (±29.7) | not comparable | -30% (React lower) | not comparable |
| Cold load, to the DOM and layout of the board | 224.0 ms (±80.4), not throttled | 320.6 ms (±64.5) | 222.4 ms (±51.6) | 85.1 ms (±21.5) | not comparable | -31% (React lower) | not comparable |
| Warm load, to the board on screen | 96.7 ms (±32.9), not throttled | 147.0 ms (±33.5) | 162.5 ms (±33.2) | 46.2 ms (±1.1) | not comparable | +11% (no significant difference) | not comparable |
| Warm load, to the DOM and layout of the board | 101.9 ms (±27.6), not throttled | 142.7 ms (±28.0) | 149.4 ms (±32.6) | 35.8 ms (±12.3) | not comparable | +1% (no significant difference) | not comparable |
| Largest Contentful Paint, cold load (Chromium) | 244.0 ms (±86.0), not throttled | 356.0 ms (±70.0) | 252.0 ms (±58.0) | 100.0 ms (±26.0) | not comparable | -27% (React lower) | not comparable |
| Transferred to show the board | 285.7 KB (±0.0), not throttled | 400.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | not comparable | -86% (React lower) | not comparable |
| DOM nodes with the board on screen | 304.0 (±0.0), not throttled | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | not comparable | +2540% (React higher) | not comparable |
| Typing in the search (median of 6 keys) | 40.0 ms (±8.7), not throttled | 64.2 ms (±14.1) | 30.8 ms (±0.9) | 30.3 ms (±0.4) | not comparable | -44% (React lower) | not comparable |
| Typing in the search, until the DOM is ready | 41.4 ms (±13.7), not throttled | 72.2 ms (±17.5) | 22.6 ms (±4.1) | 7.8 ms (±1.5) | not comparable | -67% (React lower) | not comparable |
| Marking a favorite (median of 3) | 28.2 ms (±14.8), not throttled | 44.5 ms (±16.1) | 27.5 ms (±0.9) | 28.9 ms (±1.7) | not comparable | -38% (React lower) | not comparable |
| Marking a favorite, until the DOM is ready | 12.8 ms (±6.6), not throttled | 50.9 ms (±10.3) | 13.0 ms (±4.5) | 5.0 ms (±1.3) | not comparable | -74% (React lower) | not comparable |
| Opening a work (median of 3) | 28.3 ms (±1.0), not throttled | 45.2 ms (±13.7) | 27.4 ms (±0.9) | 28.8 ms (±1.6) | not comparable | -38% (React lower) | not comparable |
| Opening a work, until the DOM is ready | 9.5 ms (±1.6), not throttled | 48.8 ms (±12.8) | 15.9 ms (±1.1) | 3.9 ms (±0.8) | not comparable | -67% (React lower) | not comparable |
| Adding a work (median of 2) | 27.2 ms (±1.3), not throttled | 44.3 ms (±8.4) | 29.1 ms (±0.8) | 28.6 ms (±0.9) | not comparable | -34% (React lower) | not comparable |
| Adding a work, until the DOM is ready | 25.6 ms (±4.9), not throttled | 41.8 ms (±10.3) | 13.3 ms (±2.7) | 4.7 ms (±0.9) | not comparable | -68% (React lower) | not comparable |
| Switching to the stats (200 cells) | 60.9 ms (±16.3), not throttled | 110.8 ms (±24.3) | 29.3 ms (±0.9) | 28.7 ms (±0.8) | not comparable | -73% (React lower) | not comparable |
| Switching to the stats, until the DOM is ready | 67.7 ms (±10.0), not throttled | 114.1 ms (±27.3) | 28.4 ms (±4.0) | 9.5 ms (±2.1) | not comparable | -74% (React lower) | not comparable |
| Switching back to the board | 45.0 ms (±2.0), not throttled | 61.6 ms (±10.1) | 130.6 ms (±24.0) | 28.8 ms (±1.1) | not comparable | +111% (React higher) | not comparable |
| Switching back to the board, until the DOM is ready | 43.3 ms (±7.2), not throttled | 64.3 ms (±20.3) | 119.0 ms (±24.3) | 8.4 ms (±1.7) | not comparable | +82% (React higher) | not comparable |
| Scrolling the list, longest frame | 33.4 ms (±0.1), not throttled | 50.0 ms (±16.7) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | not comparable | -66% (React lower) | not comparable |
| Scrolling the list, frames over 25 ms (a dropped frame) | 3.0 (±6.0), not throttled | 19.0 (±3.5) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.2 (±0.0), not throttled | 0.2 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 48.0 ms (±8.0), not throttled | 120.0 ms (±32.0) | 144.0 ms (±24.0) | 48.0 ms (±16.0) | not comparable | +20% (no significant difference) | not comparable |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0), not throttled | 6.0 ms (±41.5) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | not comparable | -100% (no significant difference) | not comparable | 

Slow 4G: round 1/15Slow 4G: round 2/15Slow 4G: round 3/15Slow 4G: round 4/15Slow 4G: round 5/15Slow 4G: round 6/15Slow 4G: round 7/15Slow 4G: round 8/15Slow 4G: round 9/15Slow 4G: round 10/15Slow 4G: round 11/15Slow 4G: round 12/15Slow 4G: round 13/15Slow 4G: round 14/15Slow 4G: round 15/15
Slow 4G (cold load, 15 rounds)

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 1837.4 ms (±4.2) | 2423.7 ms (±7.8) | 644.5 ms (±10.1) | 640.0 ms (±6.1) | -65% (React lower) | -73% (React lower) | -65% (React lower) |
| Cold load, to the DOM and layout of the board | 1844.8 ms (±6.1) | 2429.1 ms (±6.4) | 646.1 ms (±7.3) | 620.6 ms (±4.6) | -65% (React lower) | -73% (React lower) | -66% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 1852.0 ms (±6.0) | 2440.0 ms (±8.0) | 656.0 ms (±6.0) | 632.0 ms (±8.0) | -64% (React lower) | -73% (React lower) | -66% (React lower) |
| Transferred to show the board | 285.7 KB (±0.0) | 400.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -80% (React lower) | -86% (React lower) | -80% (React lower) |
| DOM nodes with the board on screen | 304.0 (±0.0) | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2540% (React higher) | +2540% (React higher) | -36% (React lower) | 
