CPU 1x

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 49.7 ms (±0.6) | 49.7 ms (±0.5) | 32.4 ms (±0.5) | 32.3 ms (±0.6) | -35% (React lower) | -35% (React lower) | -35% (React lower) |
| Cold load, to the DOM and layout of the board | 51.1 ms (±0.3) | 48.0 ms (±1.9) | 38.2 ms (±0.4) | 15.9 ms (±0.3) | -25% (React lower) | -20% (React lower) | -69% (React lower) |
| Warm load, to the board on screen | 45.6 ms (±1.5) | 45.6 ms (±0.4) | 29.3 ms (±1.8) | 29.0 ms (±0.4) | -36% (React lower) | -36% (no significant difference) | -36% (React lower) |
| Warm load, to the DOM and layout of the board | 37.2 ms (±6.4) | 37.6 ms (±4.3) | 41.8 ms (±2.1) | 15.1 ms (±0.6) | +11% (React higher) | +11% (React higher) | -60% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 60.0 ms (±0.0) | 56.0 ms (±2.0) | 48.0 ms (±0.0) | 36.0 ms (±0.0) | -20% (React lower) | -14% (React lower) | -40% (React lower) |
| Transferred to show the board | 285.7 KB (±0.0) | 400.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -80% (React lower) | -86% (React lower) | -80% (React lower) |
| DOM nodes with the board on screen | 304.0 (±0.0) | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2540% (React higher) | +2540% (React higher) | -36% (React lower) |
| Typing in the search (median of 6 keys) | 30.7 ms (±0.1) | 31.0 ms (±0.3) | 31.6 ms (±0.2) | 31.4 ms (±0.2) | +3% (no significant difference) | +2% (no significant difference) | +3% (no significant difference) |
| Typing in the search, until the DOM is ready | 11.3 ms (±0.3) | 19.9 ms (±0.6) | 4.3 ms (±0.1) | 1.4 ms (±0.1) | -62% (React lower) | -78% (React lower) | -87% (React lower) |
| Marking a favorite (median of 3) | 31.2 ms (±0.2) | 31.3 ms (±0.3) | 31.3 ms (±0.3) | 30.7 ms (±0.5) | +0% (no significant difference) | +0% (no significant difference) | -2% (no significant difference) |
| Marking a favorite, until the DOM is ready | 3.9 ms (±0.3) | 21.1 ms (±0.4) | 2.5 ms (±0.3) | 1.6 ms (±0.3) | -36% (React lower) | -88% (React lower) | -59% (React lower) |
| Opening a work (median of 3) | 31.3 ms (±0.1) | 31.2 ms (±0.2) | 30.9 ms (±0.4) | 30.5 ms (±0.6) | -2% (no significant difference) | -2% (no significant difference) | -3% (no significant difference) |
| Opening a work, until the DOM is ready | 3.8 ms (±0.3) | 22.4 ms (±0.9) | 4.2 ms (±1.1) | 1.6 ms (±0.2) | +13% (no significant difference) | -78% (React lower) | -55% (React lower) |
| Adding a work (median of 2) | 31.3 ms (±0.2) | 31.3 ms (±0.2) | 31.1 ms (±0.6) | 30.3 ms (±0.4) | -1% (no significant difference) | -1% (no significant difference) | -3% (no significant difference) |
| Adding a work, until the DOM is ready | 7.7 ms (±0.5) | 19.6 ms (±0.3) | 3.2 ms (±0.3) | 1.9 ms (±0.5) | -57% (React lower) | -83% (React lower) | -77% (React lower) |
| Switching to the stats (200 cells) | 31.3 ms (±0.2) | 31.4 ms (±0.3) | 31.4 ms (±0.4) | 30.3 ms (±0.9) | +0% (no significant difference) | +1% (no significant difference) | -3% (no significant difference) |
| Switching to the stats, until the DOM is ready | 21.1 ms (±1.1) | 26.6 ms (±2.2) | 7.5 ms (±0.8) | 3.6 ms (±1.0) | -66% (React lower) | -71% (React lower) | -82% (React lower) |
| Switching back to the board | 31.5 ms (±0.1) | 31.4 ms (±0.2) | 31.4 ms (±0.2) | 30.9 ms (±0.8) | +0% (no significant difference) | -0% (no significant difference) | -3% (no significant difference) |
| Switching back to the board, until the DOM is ready | 12.4 ms (±0.4) | 21.8 ms (±0.6) | 27.9 ms (±2.7) | 3.0 ms (±1.1) | +125% (React higher) | +29% (React higher) | -75% (React lower) |
| Scrolling the list, longest frame | 16.8 ms (±0.0) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 40.0 ms (±0.0) | 56.0 ms (±8.0) | 40.0 ms (±4.0) | 40.0 ms (±0.0) | +0% (no significant difference) | -14% (no significant difference) | +0% (no significant difference) |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) | 

CPU 4x: round 1/15CPU 4x: round 2/15CPU 4x: round 3/15CPU 4x: round 4/15CPU 4x: round 5/15CPU 4x: round 6/15CPU 4x: round 7/15CPU 4x: round 8/15CPU 4x: round 9/15CPU 4x: round 10/15CPU 4x: round 11/15CPU 4x: round 12/15CPU 4x: round 13/15CPU 4x: round 14/15CPU 4x: round 15/15
CPU 4x

SwiftUIWeb (worker) is not throttled: the throttle reached the page only: Chromium refuses the throttle for a worker. Its numbers are not a 4x CPU and are not compared with React.

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 132.4 ms (±8.6), not throttled | 197.7 ms (±10.2) | 158.0 ms (±5.8) | 48.2 ms (±0.6) | not comparable | -19% (React lower) | not comparable |
| Cold load, to the DOM and layout of the board | 132.7 ms (±4.5), not throttled | 189.2 ms (±5.3) | 150.5 ms (±3.1) | 57.5 ms (±2.1) | not comparable | -20% (React lower) | not comparable |
| Warm load, to the board on screen | 64.0 ms (±0.7), not throttled | 97.1 ms (±16.4) | 97.8 ms (±8.3) | 30.6 ms (±0.8) | not comparable | +1% (no significant difference) | not comparable |
| Warm load, to the DOM and layout of the board | 66.2 ms (±1.8), not throttled | 91.9 ms (±2.8) | 100.4 ms (±1.5) | 23.6 ms (±1.1) | not comparable | +10% (React higher) | not comparable |
| Largest Contentful Paint, cold load (Chromium) | 148.0 ms (±6.0), not throttled | 208.0 ms (±6.0) | 172.0 ms (±2.0) | 68.0 ms (±4.0) | not comparable | -17% (React lower) | not comparable |
| Transferred to show the board | 285.7 KB (±0.0), not throttled | 400.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | not comparable | -86% (React lower) | not comparable |
| DOM nodes with the board on screen | 304.0 (±0.0), not throttled | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | not comparable | +2540% (React higher) | not comparable |
| Typing in the search (median of 6 keys) | 27.5 ms (±0.5), not throttled | 37.8 ms (±3.0) | 31.2 ms (±0.4) | 31.0 ms (±0.5) | not comparable | -17% (React lower) | not comparable |
| Typing in the search, until the DOM is ready | 24.1 ms (±1.2), not throttled | 47.1 ms (±2.9) | 15.1 ms (±0.9) | 5.0 ms (±0.6) | not comparable | -67% (React lower) | not comparable |
| Marking a favorite (median of 3) | 29.4 ms (±0.5), not throttled | 30.2 ms (±0.7) | 29.6 ms (±1.0) | 30.3 ms (±0.7) | not comparable | -2% (no significant difference) | not comparable |
| Marking a favorite, until the DOM is ready | 7.7 ms (±0.6), not throttled | 32.2 ms (±1.8) | 7.8 ms (±0.8) | 3.2 ms (±0.5) | not comparable | -75% (React lower) | not comparable |
| Opening a work (median of 3) | 29.9 ms (±0.6), not throttled | 30.2 ms (±0.4) | 29.4 ms (±0.7) | 30.5 ms (±0.3) | not comparable | -3% (no significant difference) | not comparable |
| Opening a work, until the DOM is ready | 6.5 ms (±0.9), not throttled | 34.5 ms (±1.9) | 10.3 ms (±1.2) | 2.7 ms (±0.4) | not comparable | -70% (React lower) | not comparable |
| Adding a work (median of 2) | 29.6 ms (±0.6), not throttled | 29.8 ms (±0.7) | 30.4 ms (±0.7) | 29.9 ms (±0.8) | not comparable | +1% (no significant difference) | not comparable |
| Adding a work, until the DOM is ready | 16.3 ms (±1.2), not throttled | 27.3 ms (±1.5) | 9.1 ms (±1.0) | 2.8 ms (±0.4) | not comparable | -66% (React lower) | not comparable |
| Switching to the stats (200 cells) | 46.8 ms (±0.6), not throttled | 63.6 ms (±0.9) | 30.2 ms (±0.8) | 30.4 ms (±0.6) | not comparable | -52% (React lower) | not comparable |
| Switching to the stats, until the DOM is ready | 42.8 ms (±1.2), not throttled | 74.4 ms (±2.6) | 19.5 ms (±0.8) | 6.2 ms (±0.4) | not comparable | -73% (React lower) | not comparable |
| Switching back to the board | 30.1 ms (±0.8), not throttled | 29.9 ms (±0.4) | 80.8 ms (±0.4) | 30.2 ms (±0.6) | not comparable | +170% (React higher) | not comparable |
| Switching back to the board, until the DOM is ready | 26.2 ms (±0.8), not throttled | 40.9 ms (±1.4) | 79.0 ms (±1.6) | 5.5 ms (±0.8) | not comparable | +94% (React higher) | not comparable |
| Scrolling the list, longest frame | 16.8 ms (±0.0), not throttled | 33.3 ms (±0.1) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | not comparable | -50% (React lower) | not comparable |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0), not throttled | 2.0 (±2.0) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.2 (±0.0), not throttled | 0.2 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 48.0 ms (±0.0), not throttled | 88.0 ms (±4.0) | 96.0 ms (±0.0) | 40.0 ms (±4.0) | not comparable | +9% (React higher) | not comparable |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0), not throttled | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | not comparable | +0% (no significant difference) | not comparable | 

Slow 4G: round 1/15Slow 4G: round 2/15Slow 4G: round 3/15Slow 4G: round 4/15Slow 4G: round 5/15Slow 4G: round 6/15Slow 4G: round 7/15Slow 4G: round 8/15Slow 4G: round 9/15Slow 4G: round 10/15Slow 4G: round 11/15Slow 4G: round 12/15Slow 4G: round 13/15Slow 4G: round 14/15Slow 4G: round 15/15
Slow 4G (cold load, 15 rounds)

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 1848.4 ms (±6.8) | 2439.6 ms (±11.2) | 663.0 ms (±10.4) | 646.7 ms (±8.2) | -64% (React lower) | -73% (React lower) | -65% (React lower) |
| Cold load, to the DOM and layout of the board | 1856.7 ms (±6.2) | 2444.9 ms (±3.3) | 663.7 ms (±0.7) | 633.6 ms (±2.0) | -64% (React lower) | -73% (React lower) | -66% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 1864.0 ms (±4.0) | 2456.0 ms (±4.0) | 676.0 ms (±0.0) | 644.0 ms (±2.0) | -64% (React lower) | -72% (React lower) | -65% (React lower) |
| Transferred to show the board | 285.7 KB (±0.0) | 400.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -80% (React lower) | -86% (React lower) | -80% (React lower) |
| DOM nodes with the board on screen | 304.0 (±0.0) | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2540% (React higher) | +2540% (React higher) | -36% (React lower) | 
