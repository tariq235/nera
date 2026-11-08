# Definition of Done

A change is done when every box is true. The PR template mirrors this list.

## 1. Native performance
- [ ] Meets the [performance budget](performance-budget.md); PR-tier performance checks green.
- [ ] No main-thread I/O, and no timers while idle.

## 2. Security by default
- [ ] Satisfies the relevant [security requirements](security-requirements.md) with no configuration.
- [ ] Threat model updated if a trust boundary, parser, network host or entitlement changed.
- [ ] New untrusted-input parsers have a fuzzer.

## 3. Privacy by default
- [ ] No new data leaves the device without an explicit user action; any new host is in the network inventory.
- [ ] Logs use `.private` for user data.

## 4. Documented & tested
- [ ] Automated tests in every relevant [category](testing-requirements.md), on **every engine** it applies to.
- [ ] Coverage floors met and the ratchet didn't drop.
- [ ] Checklist rows ticked with evidence (`make checklists` green); public APIs have DocC comments.
- [ ] Accessibility: labels, keyboard path, and the audit passes.

## Always
- [ ] `make smoke` green locally and every required CI check green.
- [ ] Engine independence kept (no WebKit/CEF imports outside adapters).
- [ ] Clean-room confirmed. DCO sign-off on every commit.
