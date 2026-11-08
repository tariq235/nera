# 004 — Performance

Budgets: [performance budget](../docs/standards/performance-budget.md). A budget counts as met only when an automated test measures it.

- [x] **PERF-001** Budgets defined for launch, tab switch, command bar, memory, size — P0 · owner: nera · evidence: doc:docs/standards/performance-budget.md
- [x] **PERF-002** Live page cap with LRU eviction (background tabs cost no renderer memory) — P0 · owner: nera · evidence: test:PageLifecycleTests/lruEvictionNeverDiscardsTheActiveTab
- [x] **PERF-003** Library saves are debounced (no disk write per title change) — P1 · owner: nera · evidence: test:StorageTests/storeDebouncesAndFlushes
- [ ] **PERF-004** Cold launch to first frame < 500 ms, measured in CI on the fixed VM — P0 · owner: nera · evidence: planned: later
- [ ] **PERF-005** Tab switch (warm) < 16 ms, signpost-measured — P0 · owner: nera · evidence: planned: later
- [ ] **PERF-006** Command bar open < 50 ms — P0 · owner: nera · evidence: planned: later
- [x] **PERF-007** Memory-pressure handling discards background pages — P0 · owner: nera · evidence: test:PageLifecycleTests/memoryPressureFreesBackgroundPages
- [x] **PERF-008** Idle-time suspension of background tabs (30 min default) — P1 · owner: nera · evidence: test:PageLifecycleTests/idleBackgroundPagesAreSuspended
- [x] **PERF-009** Stress: 500 tabs / 50 Spaces stay responsive; no unbounded growth — P0 · owner: nera · evidence: test:BrowserCoreTests/fiveHundredTabsAcrossFiftySpaces, test:BrowserCoreTests/randomActionSequencesKeepTheLibraryConsistent
- [x] **PERF-010** Binary size budget enforced per PR (absolute budget + max 2% growth vs main) — P0 · owner: nera · evidence: ci:scripts/ci/check-binary-size.py, file:scripts/ci/data/size-budget.json
- [ ] **PERF-011** Nightly performance trend with regression alerts — P1 · owner: nera · evidence: planned: later
- [ ] **PERF-012** Energy: no timers or animations while idle (Energy Impact "Low") — P1 · owner: nera · evidence: planned: later
- [x] **PERF-014** Cross-browser benchmark (same harness, same Mac, no debugging port): launch, paint, idle CPU, wakeups, memory against Ardia and Chrome; results and gaps published — P1 · owner: nera · evidence: doc:docs/perf/benchmarks.md, file:scripts/perf/xbench.swift
- [x] **PERF-013** Chromium engine startup cost measured and budgeted — P0 · owner: nera · evidence: doc:docs/adr/0009-chromium-go-no-go.md#decision
