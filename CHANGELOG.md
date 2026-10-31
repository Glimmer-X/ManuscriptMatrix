# Changelog

## 0.9.1 — 2026-10-31

- Fixed elapsed-day badges remaining frozen while the app stays open, including matrix cells that skip redraws when their board data is unchanged.
- Relative dates now share a presentation clock that refreshes every minute and immediately after app activation, wake or a system clock change. Popovers, inspectors and history views use the same clock.
- No board format or stored manuscript data changes.

## 0.9.0 — 2026-10-26

First public release, with a fresh source history and no personal board data.

- Native macOS submission matrix with target plans, review histories, preparation stages, venue metadata and manuscript relationships.
- English and Simplified Chinese interfaces, density controls and appearance settings.
- Local JSON persistence, cross-process synchronization, validated backup/import and audited event corrections.
- Bundled universal CLI and MCP server, with explicit data-file selection, in-memory demo mode and enforced read-only access.
- Fictional demo data and screenshots, English documentation and a Chinese README.
- MIT license and a repeatable universal Developer ID signing and Apple notarization workflow.
- Fixed first-write conflict detection when creating a previously missing board.
