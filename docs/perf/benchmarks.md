# Cross-browser benchmarks

Nera measured against other Mac browsers with one harness, the same way for every browser, from outside the app:
`scripts/perf/xbench.swift` (with `scripts/perf/bench_server.py` serving the test pages).

```sh
swift scripts/perf/xbench.swift --app nera=<Nera.app> --app ardia=<Ardia.app> --app chrome=<Google Chrome.app> \
    --runs 7 --sessions 2 --idle 30 --settle 60 --out /tmp/xbench
```

## Method

- **Same conditions for every browser.** A copy of each app in a scratch folder (never a bundle the user runs), a
  fresh empty profile per run, launched with `open -n -a <app> [url]`. Browsers take turns, rotated every round, and
  each row reports the median.
- **Nobody's real data or Keychain is touched.** Chrome gets `--user-data-dir` in a throwaway folder and Chromium's
  mock keychain; Ardia its data folder there (onboarding marked done, as Ardia's own harness does) and the mock
  keychain; Nera runs with `NERA_BENCH=1`: a throwaway library and Chromium profile, the mock keychain, the
  welcome done, links open as tabs, no update check or other launch extras, and benchmark runs never count as
  crashes. (A fake `HOME` is not used: macOS then can't find the login keychain and offers to reset it.)
- **No debugging port.** Nera forbids remote debugging in release builds (SR-020), so nothing is measured over CDP.
  Paint times come from the test page itself (Paint Timing API, first-contentful-paint, reported as an absolute time
  and compared with the moment the harness launched the browser). Windows come from `CGWindowList` (first on-screen
  window ≥ 300×200). CPU time, wakeups and memory come from `proc_pid_rusage` for every process of the app (its
  bundle's executables and their children).
- **Rows:** launch → window on screen; launch → page painted; idle CPU and wakeups per second at 1 tab and at 20
  tabs (opened one by one, like links from another app); memory (`phys_footprint`, all processes) at 1 and 20 tabs;
  app size on disk. Idle is measured for 30 s after a 60 s settle.
- **Valid only on a Mac that's plugged in, with Low Power Mode off and nothing else busy.** On battery in Low Power
  Mode every launch took about 6 s (2026-11-04); those runs were thrown away.

## Results: 2026-11-04, MacBook Pro M1 Max, macOS 26.5, on power

Nera build 7 (0.1.0), Ardia 0.2.43 (notarized release), Google Chrome (installed version). 7 launches and 2
sessions per browser.

| | Nera | Ardia | Chrome |
|---|---:|---:|---:|
| Launch → window on screen (ms) | 984 | 961 | 1047 |
| Launch → page painted (ms) | 1181 | 916 | **857** |
| Idle CPU, 1 tab (% of a core) | **0.8** | 6.7 | 2.6 |
| Idle wakeups/s, 1 tab | 35 | **8** | 9 |
| Memory, 1 tab (MB) | **294** | 381 | 339 |
| App size (MB) | **353** | 359 | 1456 |

The 20-tab rows from this run aren't comparable: Nera loaded only 7 of the 20 links (a tab opened from another app
only loaded once shown). Fixed in build 8 (links from other apps start loading at once); to be re-measured.

**Where Nera stands against Ardia:** ahead on idle CPU (about 8× lower), memory (about 25 % lower) and size; even on
launch → window; behind on launch → page painted (about 0.27 s) and idle wakeups (about 4×).

## Known causes and next steps

| Gap | Cause | Next step |
|---|---|---|
| Idle wakeups | Chromium's work loop is pumped by a fixed 30-per-second timer on top of Chromium's own scheduling | Pump only on Chromium's schedule, with a slow safety timer. A first try (2 per second) cut wakeups to about 5/s in one session, but couldn't be validated: re-measure on power, including startup (Chromium may rely on the fast pump while starting). |
| Launch → window | Chromium starts on the main thread before the window is built (about 380 ms) | Start Chromium right after the first window shows, with pages queued until it's up. A first try showed the window in 643 ms but crashed (CEF objects made before CEF's library was loaded) and is reverted; the queueing it needs is in place. |
| Launch → page painted | Same startup cost, plus profile creation | Re-measure after the two items above. |

Ardia publishes its own numbers (ardia.dev) from a different Mac and harness (CDP, background mode); they aren't
comparable with these. Only same-Mac runs of this harness are.
