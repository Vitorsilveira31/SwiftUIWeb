CPU 1x

| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |
|---|---|---|---|---|---|---|---|
| Cold load, to the board on screen | 118.0 ms (±13.0) | 115.0 ms (±5.5) | 116.0 ms (±9.0) | 48.0 ms (±6.5) | -3% (no significant difference) | +3% (no significant difference) | -58% (React lower) |
| Cold load, to the DOM and layout of the board | 94.0 ms (±7.5) | 88.0 ms (±2.0) | 88.0 ms (±2.5) | 22.0 ms (±1.0) | -7% (no significant difference) | -2% (no significant difference) | -77% (React lower) |
| Warm load, to the board on screen | 81.0 ms (±15.0) | 73.0 ms (±2.0) | 81.0 ms (±2.0) | 30.0 ms (±1.0) | +0% (no significant difference) | +11% (no significant difference) | -63% (React lower) |
| Warm load, to the DOM and layout of the board | 74.0 ms (±4.0) | 66.0 ms (±1.5) | 74.0 ms (±2.0) | 10.0 ms (±2.5) | +3% (no significant difference) | +14% (React higher) | -85% (React lower) |
| Transferred to show the board | 715.3 KB (±0.0) | 689.5 KB (±0.0) | 66.6 KB (±0.0) | 66.6 KB (±0.0) | -91% (React lower) | -90% (React lower) | -91% (React lower) |
| DOM nodes with the board on screen | 303.0 (±0.0) | 303.0 (±0.0) | 8025.0 (±0.0) | 196.0 (±0.0) | +2549% (React higher) | +2549% (React higher) | -35% (React lower) |
| Typing in the search (median of 6 keys) | 31.0 ms (±0.0) | 31.0 ms (±0.0) | 31.0 ms (±0.5) | 32.0 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +3% (no significant difference) |
| Typing in the search, until the DOM is ready | 12.0 ms (±1.0) | 20.0 ms (±0.0) | 6.0 ms (±1.0) | 2.0 ms (±0.0) | -50% (React lower) | -70% (React lower) | -83% (React lower) |
| Marking a favorite (median of 3) | 65.0 ms (±0.0) | 65.0 ms (±0.5) | 65.0 ms (±1.0) | 66.0 ms (±1.0) | +0% (no significant difference) | +0% (no significant difference) | +2% (no significant difference) |
| Marking a favorite, until the DOM is ready | 47.0 ms (±1.0) | 51.0 ms (±1.5) | 50.0 ms (±1.0) | 39.0 ms (±2.0) | +9% (React higher) | +0% (no significant difference) | -17% (React lower) |
| Opening a work (median of 3) | 65.0 ms (±0.0) | 66.0 ms (±0.5) | 65.0 ms (±0.0) | 66.0 ms (±1.0) | +0% (no significant difference) | -2% (no significant difference) | +2% (no significant difference) |
| Opening a work, until the DOM is ready | 45.0 ms (±1.0) | 52.0 ms (±1.0) | 37.0 ms (±3.0) | 36.0 ms (±2.0) | -18% (React lower) | -31% (React lower) | -18% (React lower) |
| Adding a work (median of 2) | 65.0 ms (±1.0) | 65.0 ms (±1.0) | 65.0 ms (±0.0) | 65.0 ms (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
| Adding a work, until the DOM is ready | 42.0 ms (±3.0) | 52.0 ms (±6.0) | 48.0 ms (±1.0) | 35.0 ms (±0.0) | +14% (React higher) | -8% (no significant difference) | -17% (React lower) |
| Switching to the stats (200 cells) | 81.0 ms (±9.0) | 66.0 ms (±1.0) | 65.0 ms (±1.0) | 66.0 ms (±0.0) | -20% (no significant difference) | +0% (no significant difference) | -19% (no significant difference) |
| Switching to the stats, until the DOM is ready | 58.0 ms (±3.0) | 62.0 ms (±0.5) | 42.0 ms (±1.0) | 37.0 ms (±1.0) | -28% (React lower) | -32% (React lower) | -38% (React lower) |
| Switching back to the board | 65.0 ms (±0.0) | 65.0 ms (±1.0) | 102.0 ms (±1.5) | 66.0 ms (±1.0) | +57% (React higher) | +57% (React higher) | +2% (no significant difference) |
| Switching back to the board, until the DOM is ready | 46.0 ms (±2.5) | 56.0 ms (±1.5) | 95.0 ms (±1.0) | 36.0 ms (±0.0) | +107% (React higher) | +70% (React higher) | -22% (React lower) |
| Scrolling the list, longest frame | 19.0 ms (±0.0) | 19.0 ms (±0.0) | 19.0 ms (±1.0) | 19.0 ms (±1.0) | +0% (no significant difference) | +0% (no significant difference) | -5% (no significant difference) |
| Scrolling the list, frames over 25 ms (a dropped frame) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | 0.0 (±0.0) | +0% (no significant difference) | +0% (no significant difference) | +0% (no significant difference) |
