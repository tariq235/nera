# Definition of Ready

Work starts only when the item has:

- [ ] **A problem statement**: who needs it and why, in one or two sentences.
- [ ] **Acceptance criteria**: observable behavior, including what happens on errors, offline, and in private windows.
- [ ] **Engine impact**: works on both engines? Which `EngineCapabilities` does it need? What happens where unsupported?
- [ ] **Security & privacy notes**: new trust boundary, new input parser, new network host, new entitlement or permission? If yes, update the threat model *first*.
- [ ] **Checklist rows**: the IDs it will tick or add (e.g. FEAT-021, SEC-044).
- [ ] **Test plan**: which test categories it will add to.
- [ ] **Performance impact**: which budget it could affect.
- [ ] **Clean-room check**: the spec is written in our own words, with no Arc code, strings or assets.
- [ ] **Size**: fits in PRs of < 400 changed lines, or is split.
- [ ] **Feature freeze respected**: during the freeze, only foundation work and bug fixes are Ready.
