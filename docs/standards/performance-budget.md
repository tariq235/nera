# Performance budget

Reference hardware: **an M1 Max Mac** for macOS; **iPhone 15 / iPad (A16)** simulators for relative trends and a physical device for releases. A budget counts as met only when an automated test measures it ([checklist 004](../../checklists/004-performance.md)).

| Metric | Budget | Measured by | Tier |
|---|---|---|---|
| Cold launch → first interactive frame (macOS) | < 500 ms (WebKit), budget from measurements (Chromium) | `XCTApplicationLaunchMetric` | PR smoke + nightly |
| Command bar open → focused field | < 50 ms | signpost interval in UI test | nightly |
| Tab switch, warm page | < 16 ms (one frame) | signpost interval | nightly |
| Tab switch, discarded page → first paint | < 300 ms | signpost interval | nightly |
| Reducer action (any) | < 1 ms at 500 tabs / 50 Spaces | Swift Testing benchmark | PR |
| Library save (500 tabs) | < 20 ms, off the main thread | benchmark | nightly |
| Memory, idle background tab | 0 MB renderer (discarded by LRU / memory pressure) | stress test | nightly |
| Memory, main process with 500 tabs in sidebar | < 150 MB | stress test | nightly |
| App size: iOS | < 20 MB | CI artifact check | PR |
| App size: macOS | set from measurements (target ≤ 250 MB) | CI artifact check | PR |
| Idle CPU (no media playing) | ~0%, no timers firing faster than 1/min | Instruments trace (manual, per release) | release |

## Regression policy

- **PR:** fails if the app size grows > 2% or launch time > 10% versus `main`.
- **Nightly:** results are stored as a time series. Alert on a > 5% regression sustained over 3 nights.
- A budget may change only through a PR that updates this file with the reason.
