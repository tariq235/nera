# ADR-0001: Clean-room development

**Status:** Accepted · **Date:** 2026-10-25 (public wording 2026-11-05)

## Decision

Nera's code, design, text and assets are original. Behavior is implemented from public platform documentation and
our own written descriptions of what a feature should do. No code, assets or text from closed-source browsers enter
the repository. Reading other browsers' data files that users export or keep, so they can import them, is
interoperability and is allowed. Full rules: [CLEAN_ROOM.md](../../CLEAN_ROOM.md).

## Why

- Copyright and trade-dress safety for an open-source project.
- Specifications written in our own words are more useful to contributors than anyone else's code would be.

## Consequences

- Importers read other browsers' file formats only.
- Default keyboard shortcuts follow common conventions; visual design, names and copy are original.
