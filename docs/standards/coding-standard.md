# Coding standard (incl. Swift style)

Style is enforced by tools, not by review comments. If a rule here isn't enforced yet, add the tool rule rather than relying on people.

## Tooling (enforced in CI)

| Tool | Config | Runs |
|---|---|---|
| `swift format` (ships with the Swift 6 toolchain) | `.swift-format` | `make format` locally; `swift format lint --strict` in CI |
| SwiftLint | `.swiftlint.yml` (safety rules; layout belongs to `swift format`). Test-only code has local configs allowing force unwraps/casts | CI, `--strict` |
| Swift compiler | Swift 6 language mode, `StrictConcurrency=complete`, upcoming features `ExistentialAny`, `InternalImportsByDefault`, **warnings as errors** in CI | always |

## Language rules

1. **Concurrency:** UI and engine adapters are `@MainActor`. Shared mutable state is an actor or `@MainActor`. `@unchecked Sendable` needs a comment explaining the lock, and is only allowed in L0 or TestSupport.
2. **No force-unwraps or `try!`** outside tests. Use `guard … else` with an explicit failure path.
3. **No `fatalError`** in shipped code paths except for genuinely impossible programmer errors, with a message.
4. **Errors:** typed `enum … : Error` per module. Never swallow errors silently: either handle, surface to the user, or log with `.private` data.
5. **Access control:** `internal` by default; `public` only for the module's API; `private` for helpers. Mark `public import` only when types are re-exported.
6. **Value types first.** Models are `struct`/`enum`, `Codable`, `Hashable`, `Sendable`. Classes only for identity/lifecycle (stores, pages, adapters).
7. **Pure functions** for logic (reducers, policies, parsers): no `Date()`, `UUID()` or I/O inside; inject them.
8. **Untrusted input** (pages, files, URLs) is parsed by total functions that return `nil`/errors, never trap. Every such parser gets a fuzzer.
9. **Logging:** `os.Logger` with a per-module subsystem. URLs, titles and user content are always `privacy: .private`.
10. **No engine types outside adapters** (AP-1).

## Naming & layout

- Types `UpperCamelCase`, members `lowerCamelCase`, acronyms as words (`urlString`, `HTTPSOnly` → `httpsOnly`).
- One primary type per file, with the file named after it. Extensions for protocol conformances in the same file, marked `// MARK: -`.
- Tests: `<Thing>Tests.swift`, test names describe behavior: `closingPinnedTabKeepsItButUnloads`.

## Comments

Explain *why*, not *what*. Link the spec or ADR for non-obvious behavior (`// SR-012`, `// ADR-0009`). No commented-out code.

## Commits & PRs

- Conventional commit titles (`feat(sidebar): …`, `fix(engine): …`, `docs: …`, `test: …`, `ci: …`).
- DCO sign-off (`git commit -s`).
- PRs < 400 changed lines where possible. Each PR follows the [Definition of Done](definition-of-done.md).

## Guards that run on every PR

`make lint` (format, SwiftLint, warnings-as-errors) · `make guards` (secrets, licenses, clean room, Arc naming, dependency vulnerabilities) · `make docs` (public-API docs, links, checklists, DocC) · `make architecture` · `make size`. `make smoke` runs all of them plus the tests and builds.
