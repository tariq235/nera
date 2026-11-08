# ADR-0003: State management — pure reducer + Observation, no TCA (for now)

**Status:** Accepted · **Date:** 2026-10-25

## Context

Large Swift browsers often use The Composable Architecture (TCA) across many modules. TCA gives testability and time-travel debugging, but costs compile time, learning curve and a large dependency.

## Decision

- One value-type `BrowserState`, mutated only by `Reducer.reduce(state, action, env) -> [Effect]`. It's pure, deterministic (injected clock and UUIDs), and fully unit-tested.
- `BrowserStore` (`@Observable`, `@MainActor`) is the single source of truth for SwiftUI.
- Side effects (load page, discard page) are returned as `Effect` values and executed by `PageManager`, never inside the reducer.
- Every service (persistence, engine, sync) sits behind a protocol with a test double.

## Revisit when

- The reducer passes ~1,500 lines, or features need scoped child stores → split into feature reducers (same pattern), and consider TCA.
- We need an action log for bug reports → add an `ActionRecorder` middleware (cheap with this design).
