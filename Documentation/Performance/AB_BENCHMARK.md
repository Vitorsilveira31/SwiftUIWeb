# A/B benchmark for browser apps

`Tools/perf-ab.mjs` answers one question: **is bundle B faster or slower than bundle A, by more than the noise of the
machine?** It exists because numbers from two separately started servers, or taken at different times, drift by 15 to
30 percent. The tool removes that drift by construction:

- Both bundles are served at the same time (`Tools/bun-server.ts`, two ports).
- The same scenario runs alternately A, B, A, B, ... each time in a fresh browser and a fresh context.
- Per interaction and metric it reports the median and the spread (IQR) of the runs of each side, the relative change,
  a bootstrap interval of the change and a p value. The comparison is **paired by round**: the A run and the B run of
  one round happen one after the other, so the load other processes put on the machine at that moment hits both, and
  the per-round difference cancels it (a load that drifts by a factor of two over a session is common). The change is
  the median of the per-round differences, its 99 percent interval a bootstrap over rounds, the test a Wilcoxon
  signed-rank test. A difference is reported only when the interval excludes zero, p is below 0.01 and the change is at
  least 5 percent (and half a millisecond for times); everything else is `-`, "no significant difference".
  `--unpaired` compares the two samples as independent instead (bootstrap and Mann-Whitney).
- An **A/A self-check** (`--aa`) serves the same bundle on both ports. It must come out with no significant
  difference; run it on a machine before trusting its A/B numbers.

## One command

```sh
bun Tools/perf-ab.mjs --a .build/perf/base --b .build/perf/change --scenario path/to/scenario.mjs \
  --rounds 20 --cpu 1,4 --api-origin http://127.0.0.1:8081
bun Tools/perf-ab.mjs --a .build/perf/base --aa --scenario path/to/scenario.mjs --rounds 12 --cpu 1,4   # self-check
```

`bun install` first (Playwright). Measure **release** bundles; a debug bundle is about 15 times slower to interact with.
Build one bundle per variant and copy it to a directory of its own (`cp -R <app>/.build/browser/<Product> <dir>`), so a
rebuild does not change the A side while a run is going. The options:

| Option | Meaning |
| --- | --- |
| `--a`, `--b` | Bundle directories. `--aa` serves `--a` on both ports instead of `--b`. |
| `--scenario` | Scenario module (below). |
| `--rounds` | Runs per side and CPU rate; at least 10, or the signed-rank test cannot reach p < 0.01. Pairing finds a 15 percent change in 12 rounds when the load drifts and the runs are otherwise steady; independent samples with 15 percent noise need 20 runs for 25 percent (both measured in `Tools/test-perf-ab-stats.mjs`). Smaller changes need more rounds. |
| `--unpaired` | Treat the samples as independent. |
| `--cpu` | Comma separated CPU throttling rates (`Emulation.setCPUThrottlingRate`, Chromium only), for example `1,4`. Each rate is its own alternating campaign. |
| `--engine`, `--order` | `chromium` (default), `webkit` or `firefox`; `ab` (A, B, A, B) or `abba` (second pair swapped). |
| `--port-a`, `--port-b` | Default 8190 and 8191. |
| `--api-origin`, `--api-path` | Proxy of both servers (`SWIFTUIWEB_API_ORIGIN`, `SWIFTUIWEB_API_PATH`, default path `/api`). |
| `--frame-rate` | `uncapped` (default) or `default`; see frame pacing. |
| `--metrics`, `--only` | The metrics and the interactions printed; the JSON always holds all. |
| `--alpha`, `--min-effect` | Significance level (0.01) and smallest relative change (0.05). |
| `--json`, `--markdown` | Write every sample and comparison / the printed tables. |

A run that throws is retried once; a second failure stops the campaign (`--keep-going` records it and continues).

## What is measured

The page opens with `?swuidiag`. Around each interaction the tool calls `__performanceMetrics.reset()` and reads
`snapshot()` once the page is quiet (no commit and no long task for `quietMs`, at most `maxMs`), so every number belongs
to that interaction only:

| Metric | Source |
| --- | --- |
| `commits`, `commitMs`, `commitMsPerCommit`, `maxCommitMs` | `commits`, `commitDurationMs`, `maxCommitDurationMs` |
| `layoutMs`, `layoutPasses` | `diagnostics.layoutUpdateMs`, `layout.passes` |
| `domPatchMs`, `htmlParseMs`, `snap.*` | the other `diagnostics` timers and every numeric field of the snapshot, including the finer layout timers (`snap.layout.*`, the object `__embeddedSession.layoutMetrics`) |
| `longTaskCount`, `longTaskSumMs`, `longTaskMaxMs`, `blockingMs` | `PerformanceObserver` `longtask` (tasks over 50 ms that started in the window); `blockingMs` is the part over 50 ms |
| `frames`, `share8`, `share16`, `slowFrames16`, `jankMs`, `frameP95`, `frameMax` | `requestAnimationFrame` timestamps, see below |
| `windowMs`, `activeMs` | the whole window and the part up to the last commit or long task |

Every scenario also gets a `(whole scenario)` row: sums of the additive metrics and the maximum of the others. It has
the most statistical power and the fewest comparisons; read it first.

### Frame pacing

Headless Chromium caps `requestAnimationFrame` at 60 Hz. With `--frame-rate uncapped` the tool launches with
`--disable-frame-rate-limit --disable-gpu-vsync`, which lifts the cap: idle frames arrive about every 0.3 ms
(measured), so a frame is late only when the main thread was busy. `share8` and `share16` are the percentage of frame
intervals within 8.4 ms and 16.8 ms (the 120 Hz and 60 Hz budgets with timestamp rounding) between the start of the
interaction and its last commit. Because uncapped idle frames are cheap, those shares stay high even for a janky
interaction; **`slowFrames16` (count), `jankMs` (time over budget) and `frameMax` show jank, the shares show how much of
the interaction was smooth**. With `--frame-rate default` the 60 Hz cap stays, the intervals are 16.7 ms when idle and
`share16` measures the same thing with less resolution. On engines other than Chromium the flags are not passed, so the
cap remains. The recorder runs only while an interaction is measured, equally on both sides.

### Validation of the tool itself

On a large app (release bundle, 14 rounds, machine shared with other builds): the A/A self-check flagged 0
of 2184 comparisons at CPU 1x and at 4x; the whole-scenario run-to-run spread was 13 percent at 1x and 55 percent at 4x,
and the observed A against A' difference of the whole-scenario `commitMs` was +7 percent (p 0.02, below the bar) at 1x.
A copy of the bundle with a deliberate cost injected (15 microseconds per `getBoundingClientRect`) was reported as
slower: `commitMs` +20 percent, `layoutMs` +28 percent, `longTaskSumMs` +49 percent, all at p 0.001. Treat a whole-scenario
change under about 10 percent at 1x as noise.

## Scenario modules

A scenario is an ES module whose default export is:

```js
export default {
  name: "my-app", viewport: { width: 1280, height: 800 }, path: "/",
  warmupMs: 1500, quietMs: 300, maxMs: 2500,     // defaults; quietMs/maxMs can be set per interaction
  async prepare({ context, base, env }) {},       // optional: before the page opens (sign in, cookies)
  async ready({ page, context, base }) {},        // optional: wait until the app is usable
  async run({ page, context, base, interact, cpu }) {
    await interact("open search", async () => { await page.click("button.search"); });
    await interact("navigate", async () => { /* ... */ }, { quietMs: 400 });
  }
};
```

`interact(name, action, { quietMs, maxMs })` is the measured unit. Keep actions deterministic and do not wait with fixed
sleeps for the app: the tool waits until the page is quiet. Give each interaction a unique name.

## Reading a result

- Trust the verdict column, not the delta column: a 20 percent delta inside the spread is noise. The line "differences
  beyond noise" counts the flagged comparisons; with some 170 metrics per interaction a few false flags are expected in
  the unprinted ones at alpha 0.01 even in an A/A run, so judge the printed headline metrics and the whole-scenario row.
- A change that cannot trigger on the measured interactions reads as "no significant difference" everywhere. Check
  that the scenario exercises the code you changed (look at the `snap.*` counters) before concluding anything.
- Machine load is shared by both sides but not constant: the spread line ("run-to-run spread") tells how noisy the
  session was. On a busy machine raise `--rounds`, or run again when the load is lower.
- Do not compare numbers between two invocations. Compare A and B inside one.

`bun Tools/perf-ab-summary.mjs report.json --side both` prints the median (IQR) table of the runs in a `--json` report,
one row per interaction; with `--aa` reports it is the baseline of the bundle.

`Tools/test-perf-ab-stats.mjs` (run by `make tools-test`) covers the statistics: the quantiles, the Mann-Whitney and
Wilcoxon tests, the bootstrap interval, the false-positive rate of A/A samples (independent and paired, under drift),
the power for a shift and the summary table.
