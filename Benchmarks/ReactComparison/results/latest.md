CPU 1x

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 48.5 ms (±0.3) | 48.2 ms (±0.4) | 31.3 ms (±0.3) | 31.1 ms (±0.5) | -35% (React lower) | -35% (React lower) | -36% (React lower) |
| Cold load, to the DOM and layout of the board | 50.9 ms (±0.7) | 47.0 ms (±0.5) | 38.3 ms (±0.8) | 15.9 ms (±0.3) | -25% (React lower) | -19% (React lower) | -69% (React lower) |
| Warm load, to the board on screen | 45.6 ms (±0.5) | 45.6 ms (±0.5) | 30.6 ms (±1.4) | 29.4 ms (±0.4) | -34% (React lower) | -33% (no significant difference) | -36% (React lower) |
| Warm load, to the DOM and layout of the board | 38.1 ms (±0.6) | 37.8 ms (±1.8) | 41.7 ms (±8.0) | 14.8 ms (±1.6) | +10% (no significant difference) | +9% (no significant difference) | -61% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 60.0 ms (±4.0) | 56.0 ms (±0.0) | 48.0 ms (±0.0) | 36.0 ms (±0.0) | -13% (React lower) | -14% (React lower) | -33% (React lower) |
| Transferred to show the board | 276.3 KB (±0.0) | 390.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -79% (React lower) | -85% (React lower) | -79% (React lower) |
| DOM nodes with the board on screen | 304.0 (±0.0) | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2540% (React higher) | +2540% (React higher) | -36% (React lower) |
| Typing in the search (median of 6 keys) | 30.7 ms (±0.4) | 31.1 ms (±0.1) | 31.5 ms (±0.1) | 31.4 ms (±0.1) | +3% (no significant difference) | +1% (no significant difference) | +2% (no significant difference) |
| Typing in the search, until the DOM is ready | 11.3 ms (±0.2) | 20.1 ms (±0.6) | 4.3 ms (±0.1) | 1.4 ms (±0.1) | -62% (React lower) | -79% (React lower) | -88% (React lower) |
| Marking a favorite (median of 3) | 31.3 ms (±0.4) | 31.3 ms (±0.2) | 31.3 ms (±0.3) | 30.7 ms (±0.7) | -0% (no significant difference) | +0% (no significant difference) | -2% (no significant difference) |
| Marking a favorite, until the DOM is ready | 3.7 ms (±0.4) | 21.1 ms (±0.9) | 2.4 ms (±0.2) | 1.6 ms (±0.3) | -38% (React lower) | -89% (React lower) | -59% (React lower) |
| Opening a work (median of 3) | 31.4 ms (±0.5) | 31.2 ms (±0.1) | 31.1 ms (±0.5) | 30.4 ms (±0.7) | -1% (no significant difference) | -0% (no significant difference) | -3% (no significant difference) |
| Opening a work, until the DOM is ready | 3.6 ms (±0.2) | 21.9 ms (±1.3) | 4.1 ms (±1.2) | 1.6 ms (±0.6) | +14% (no significant difference) | -81% (React lower) | -58% (React lower) |
| Adding a work (median of 2) | 31.4 ms (±0.2) | 31.4 ms (±0.2) | 31.3 ms (±0.5) | 30.4 ms (±0.5) | -0% (no significant difference) | -0% (no significant difference) | -4% (no significant difference) |
| Adding a work, until the DOM is ready | 7.6 ms (±0.4) | 19.5 ms (±0.7) | 3.0 ms (±0.4) | 1.7 ms (±0.4) | -61% (React lower) | -87% (React lower) | -78% (React lower) |
| Switching to the stats (200 cells) | 31.4 ms (±0.4) | 31.4 ms (±0.5) | 31.5 ms (±0.5) | 30.4 ms (±1.3) | +1% (no significant difference) | +1% (no significant difference) | -3% (no significant difference) |
| Switching to the stats, until the DOM is ready | 20.7 ms (±1.2) | 25.5 ms (±2.6) | 8.1 ms (±1.5) | 3.5 ms (±1.4) | -62% (React lower) | -72% (React lower) | -85% (React lower) |
| Switching back to the board | 31.5 ms (±0.7) | 31.5 ms (±0.3) | 31.4 ms (±0.2) | 31.2 ms (±0.5) | -0% (no significant difference) | -1% (no significant difference) | -1% (no significant difference) |
| Switching back to the board, until the DOM is ready | 12.6 ms (±0.3) | 21.9 ms (±0.8) | 29.7 ms (±2.6) | 3.0 ms (±1.4) | +136% (React higher) | +36% (React higher) | -75% (React lower) |
| Scrolling the list, longest frame | 16.8 ms (±0.0) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 40.0 ms (±4.0) | 48.0 ms (±0.0) | 40.0 ms (±0.0) | 40.0 ms (±0.0) | +0% (no significant difference) | -17% (no significant difference) | +0% (no significant difference) |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) | 

CPU 4x: round 1/15CPU 4x: round 2/15CPU 4x: round 3/15CPU 4x: round 4/15CPU 4x: round 5/15CPU 4x: round 6/15CPU 4x: round 7/15CPU 4x: round 8/15CPU 4x: round 9/15CPU 4x: round 10/15CPU 4x: round 11/15CPU 4x: round 12/15CPU 4x: round 13/15CPU 4x: round 14/15CPU 4x: round 15/15
CPU 4x

SwiftUIWeb (worker) is not throttled: the throttle reached the page only: Chromium refuses the throttle for a worker. Its numbers are not a 4x CPU and are not compared with React.

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 135.6 ms (±14.2), not throttled | 187.0 ms (±9.2) | 155.3 ms (±15.3) | 47.1 ms (±4.4) | not comparable | -20% (React lower) | not comparable |
| Cold load, to the DOM and layout of the board | 136.6 ms (±10.0), not throttled | 182.4 ms (±11.7) | 148.1 ms (±11.3) | 56.0 ms (±5.0) | not comparable | -19% (React lower) | not comparable |
| Warm load, to the board on screen | 64.3 ms (±1.1), not throttled | 81.4 ms (±16.6) | 97.8 ms (±16.1) | 30.7 ms (±0.4) | not comparable | +21% (React higher) | not comparable |
| Warm load, to the DOM and layout of the board | 68.8 ms (±8.4), not throttled | 88.4 ms (±10.9) | 98.3 ms (±4.0) | 23.5 ms (±1.5) | not comparable | +11% (no significant difference) | not comparable |
| Largest Contentful Paint, cold load (Chromium) | 152.0 ms (±12.0), not throttled | 200.0 ms (±12.0) | 168.0 ms (±12.0) | 68.0 ms (±4.0) | not comparable | -16% (React lower) | not comparable |
| Transferred to show the board | 276.3 KB (±0.0), not throttled | 390.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | not comparable | -85% (React lower) | not comparable |
| DOM nodes with the board on screen | 304.0 (±0.0), not throttled | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | not comparable | +2540% (React higher) | not comparable |
| Typing in the search (median of 6 keys) | 27.6 ms (±0.9), not throttled | 40.0 ms (±6.5) | 31.4 ms (±0.8) | 30.8 ms (±0.7) | not comparable | -23% (React lower) | not comparable |
| Typing in the search, until the DOM is ready | 24.7 ms (±2.3), not throttled | 44.5 ms (±3.5) | 14.8 ms (±1.3) | 4.7 ms (±1.2) | not comparable | -69% (React lower) | not comparable |
| Marking a favorite (median of 3) | 29.9 ms (±0.9), not throttled | 30.1 ms (±1.2) | 29.6 ms (±1.1) | 30.3 ms (±1.0) | not comparable | +0% (no significant difference) | not comparable |
| Marking a favorite, until the DOM is ready | 7.1 ms (±1.4), not throttled | 32.2 ms (±1.5) | 7.2 ms (±1.6) | 2.9 ms (±0.7) | not comparable | -78% (React lower) | not comparable |
| Opening a work (median of 3) | 30.0 ms (±1.4), not throttled | 30.1 ms (±0.8) | 29.8 ms (±1.4) | 30.3 ms (±0.5) | not comparable | -2% (no significant difference) | not comparable |
| Opening a work, until the DOM is ready | 6.3 ms (±1.2), not throttled | 33.3 ms (±4.5) | 9.6 ms (±1.9) | 2.3 ms (±0.8) | not comparable | -71% (React lower) | not comparable |
| Adding a work (median of 2) | 29.9 ms (±0.8), not throttled | 29.8 ms (±1.2) | 30.4 ms (±0.7) | 30.3 ms (±0.7) | not comparable | +1% (no significant difference) | not comparable |
| Adding a work, until the DOM is ready | 15.5 ms (±1.3), not throttled | 26.0 ms (±1.8) | 7.8 ms (±2.6) | 2.7 ms (±0.6) | not comparable | -71% (React lower) | not comparable |
| Switching to the stats (200 cells) | 31.5 ms (±16.1), not throttled | 63.4 ms (±0.9) | 30.5 ms (±0.7) | 30.7 ms (±0.6) | not comparable | -51% (React lower) | not comparable |
| Switching to the stats, until the DOM is ready | 41.9 ms (±2.8), not throttled | 70.7 ms (±6.0) | 19.3 ms (±1.9) | 5.9 ms (±0.7) | not comparable | -73% (React lower) | not comparable |
| Switching back to the board | 30.4 ms (±0.3), not throttled | 30.3 ms (±15.2) | 80.8 ms (±0.4) | 30.8 ms (±1.1) | not comparable | +167% (React higher) | not comparable |
| Switching back to the board, until the DOM is ready | 26.3 ms (±2.0), not throttled | 39.7 ms (±6.3) | 77.8 ms (±2.8) | 4.9 ms (±1.0) | not comparable | +93% (React higher) | not comparable |
| Scrolling the list, longest frame | 16.8 ms (±0.0), not throttled | 33.3 ms (±0.1) | 16.8 ms (±0.0) | 16.8 ms (±0.0) | not comparable | -50% (React lower) | not comparable |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0), not throttled | 1.0 (±1.5) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Cumulative Layout Shift, the whole scenario, times 1000 (Chromium) | 0.2 (±0.0), not throttled | 0.2 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | not comparable | -100% (React lower) | not comparable |
| Interaction to Next Paint, the slowest input of the scenario (Chromium) | 48.0 ms (±0.0), not throttled | 88.0 ms (±8.0) | 88.0 ms (±8.0) | 40.0 ms (±8.0) | not comparable | +9% (no significant difference) | not comparable |
| Main thread blocked (long tasks over 50 ms) | 0.0 ms (±0.0), not throttled | 0.0 ms (±0.0) | 0.0 ms (±0.0) | 0.0 ms (±0.0) | not comparable | +0% (no significant difference) | not comparable | 

Slow 4G: round 1/15Slow 4G: round 2/15Slow 4G: round 3/15Slow 4G: round 4/15Slow 4G: round 5/15Slow 4G: round 6/15Slow 4G: round 7/15Slow 4G: round 8/15Slow 4G: round 9/15Slow 4G: round 10/15Slow 4G: round 11/15Slow 4G: round 12/15Slow 4G: round 13/15Slow 4G: round 14/15Slow 4G: round 15/15
Slow 4G (cold load, 15 rounds)

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 1787.6 ms (±15.4) | 2364.1 ms (±14.5) | 649.6 ms (±14.0) | 642.2 ms (±8.6) | -64% (React lower) | -73% (React lower) | -64% (React lower) |
| Cold load, to the DOM and layout of the board | 1792.4 ms (±17.8) | 2371.4 ms (±11.3) | 652.3 ms (±10.5) | 624.9 ms (±7.7) | -64% (React lower) | -72% (React lower) | -65% (React lower) |
| Largest Contentful Paint, cold load (Chromium) | 1800.0 ms (±20.0) | 2380.0 ms (±14.0) | 664.0 ms (±12.0) | 636.0 ms (±8.0) | -63% (React lower) | -72% (React lower) | -65% (React lower) |
| Transferred to show the board | 276.3 KB (±0.0) | 390.0 KB (±0.0) | 57.4 KB (±0.0) | 57.4 KB (±0.0) | -79% (React lower) | -85% (React lower) | -79% (React lower) |
| DOM nodes with the board on screen | 304.0 (±0.0) | 304.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2540% (React higher) | +2540% (React higher) | -36% (React lower) | 
