# Frame-time budgets

`FRAME_BUDGETS.json` holds the frame-time targets of the browser apps: 120 fps most of the time, never below 60. They are
part of the performance contracts (see [`PERFORMANCE_CONTRACTS.md`](PERFORMANCE_CONTRACTS.md)) but measured by an
application's own interaction scenario, because a frame budget only means something for a real screen. Every budget is
in **report** mode: the check prints what is over and exits 0. Switch a budget (`"enforcement": "enforce"`) or a whole run
(`--mode enforce`) when the numbers are met.

```sh
# measure a built bundle with a scenario module and evaluate
make perf-frames BUNDLE=<built bundle dir> SCENARIO=<scenario.mjs> FRAME_ARGS="--rounds 3 --api-origin http://127.0.0.1:8081"
# evaluate a measurement file again (default .build/performance/browser-frames.json)
make perf-frames-check [FRAMES=file.json] [FRAME_ARGS="--mode enforce --only-problems"]
bun Tools/test-frame-budgets.mjs          # the evaluation logic, no browser (part of `make integrated-check`)
```

## Profiles and budgets

| Profile | CPU throttling | Budgets |
| --- | --- | --- |
| `desktop` | none | per-commit main-thread time p95 at most 8.3 ms (one 120 Hz frame) per interaction and over all commits; no long task (over 50 ms) in any interaction; at least 99% of the active time in frames of at most 16.7 ms; the share within 8.3 ms is reported |
| `phone` | 4x (`Emulation.setCPUThrottlingRate`) | no frame over 16.7 ms per interaction, and at least half of the interactions without one; the share of time within 16.7 ms, long tasks and the p95 commit time are reported |

A budget has a `profile`, a `metric`, a `scope` (`each` interaction, or `pooled` over all of them), a `max` or `min` (none:
the value is only reported, status `info`) and optionally an `enforcement`. The metrics are described in the file.

## Measurements

`Tools/frame-measure.mjs` runs a scenario module (the contract of the A/B benchmark scenarios: `prepare`, `ready`,
`run({ page, interact })`) in a fresh headless browser per profile and round (`--rounds`, pooled), with `?swuidiag`. Per
interaction it resets the runtime counters, runs the action, waits until the page has been quiet for the scenario's
`quietMs` and records:

- **the duration of every commit**, from the running `commitDurationMs` total read in the `commit-phase` event (the event
  fires before a commit's own time is added, so the difference between two events is the earlier commit). The p95 is a
  nearest-rank percentile over these, so more rounds mean more samples; `commits`, `commitMs`, `commitMsPerCommit` and
  `maxCommitMs` use the names of the A/B benchmark;
- **long tasks** (`longTaskCount`, `longTaskSumMs`, `longTaskMaxMs`, `blockingMs`) from a `longtask` PerformanceObserver;
- **frame intervals** from `requestAnimationFrame` timestamps between the start of the interaction and its last commit or
  long task. `timeShare16` and `timeShare8` are the percent of that time spent in intervals of at most 16.7 / 8.3 ms
  (each plus 0.1 ms of timestamp rounding). They are time-weighted on purpose: headless Chromium is run with
  `--disable-frame-rate-limit --disable-gpu-vsync` so the 60 Hz cap does not hide a 120 Hz result, and an uncapped
  `requestAnimationFrame` fires far more often than a display refreshes, which would inflate a count of frames. The
  count-based `share8` and `share16` (the A/B benchmark's) are recorded too. `slowFrames16`, `jankMs`, `frameP95` and
  `frameMax` complete the set.

The measurement file lists every interaction of every profile (`profiles.<name>.interactions.<interaction>`), so another
tool can read it; `Tools/frame-budgets.mjs evaluate` turns it into a table and a JSON report (`--json`, `--markdown`).
Exit status: 0 unless a budget that is in enforce mode is over or has no measurement.

## Caveats

- Absolute limits on a shared machine drift by 15 to 30 percent between runs. They are there to show large regressions and
  progress; use the A/B benchmark (`perf-ab`) to compare two builds.
- Run it on a quiet machine. Other work on the same CPU (builds, other browsers) inflates every number; a
  load average near 100 roughly doubles the commit times.
- With `--rounds` above 1 the counts (`commits`, `longTaskCount`, `slowFrames16`) add up over the rounds and the commit
  durations are pooled; a `max: 0` count budget therefore means "no round had one".
- The frame shares are time-weighted over the active part of an interaction (from its start to its last commit or long
  task), so a short interaction with one long stall has a low share even though the page is idle afterwards.
- A debug bundle is about 15 times slower than a release one. Budgets are for release builds only.
- CPU throttling slows JavaScript and the Wasm only; layout, paint and compositing of the browser are not throttled, so the
  `phone` profile understates a real phone's frame time.
- WebKit has no CPU throttling or long-task observer; the runner needs Chromium.
