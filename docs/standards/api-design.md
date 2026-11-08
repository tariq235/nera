# API design

Applies to every module's `public` surface, and especially to the **engine contract** (`EngineKit`), the most important API in the codebase.

## General rules

1. **Small and intention-revealing.** Expose behaviors (`load(_:)`, `send(_:)`), not internals. If a caller needs a property only for a test, it isn't public.
2. **Values in, values out.** Prefer `struct`/`enum` parameters and results over callbacks with many arguments.
3. **Async:** `async` for one-shot work. Use a delegate or `AsyncStream` for ongoing events; never both for the same event.
4. **Errors are typed and documented.** Every `throws` lists what it throws in the DocC comment.
5. **Every public symbol has a DocC comment.** CI builds DocC with warnings as errors.
6. **Deprecate, then remove.** `@available(*, deprecated, message:)` for one minor release before removal.

## Engine contract rules (EngineKit)

1. **Engine-neutral types only.** No `WK*`, `Cef*`, `NSView` subclasses or engine enums in signatures, except `PlatformView` for hosting.
2. **Typed events, not stringly-typed messages.** Page → app communication goes through `WebPageDelegate` with typed event methods.
3. **Requests carry a one-shot `Decision`.**
   - Every request crossing TB1 (permission, download, JS dialog, file chooser, HTTP auth, certificate error, new window, external protocol) gives the app a `Decision<Answer>` responder.
   - It must be answered exactly once. A second answer is ignored and asserts in Debug.
   - **If it is never answered, it resolves to the safe default (deny/cancel) when released.**
4. **Capabilities are declared.** `EngineCapabilities` lists what an engine supports. Features check capabilities, and unsupported rows appear in the parity matrix.
5. **Security policy lives above the engine.** Adapters must call `SecurityPolicy.NavigationPolicy` for every main-frame navigation and must not add their own allow-rules.
6. **Conformance before merge.** A contract change ships with conformance tests, run against every engine (fakes included).
7. **Main-actor isolated.** The contract is `@MainActor`; adapters hop to engine threads internally.

## Versioning

Internal modules version with the app. If EngineKit is ever published for third-party engines, it gets SemVer and a compatibility policy (ADR first).
