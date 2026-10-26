# Privacy and data handling

## Local storage

The production app stores one board in `~/Library/Application Support/ManuscriptMatrix/board-v1.json`. A neighboring lock file coordinates writers. Interface preferences use the app's macOS UserDefaults domain. Missing files load as an empty board; the app never seeds personal data automatically.

The JSON board contains venue metadata, manuscript titles, targets, submission events and notes, relationships, and correction history. The app does not encrypt it. Filesystem permissions, FileVault, your backups and account security determine who can access it.

The app and bundled MCP server implement no telemetry, advertising, accounts, cloud sync or board upload. Release signing and notarization contact Apple during the maintainer's build process; users' boards are not included in the submitted bundle.

## Export, import and removal

An exported backup is a complete copy of the board and may include archived entities and corrected events. Treat exports as private. Import validates an archive and replaces the current board. Session undo remains available until exit or a genuinely external update invalidates stale undo history.

Replacing or removing the app bundle does not remove the separate board or preferences. To remove personal data deliberately, quit the app and MCP clients, then remove the app's data directory yourself. Repository scripts never perform that removal.

## Isolation

`--demo` selects an in-memory fictional board before constructing a persistent repository. Changes disappear on exit. Screenshot export uses the same boundary and command-line preference overrides, without a personal board or desktop capture.

The CLI's `--board FILE` option selects an explicit file. It does not migrate, copy or modify the default personal board. Demo and explicit-file options are mutually exclusive. Tests use disposable directories with scoped cleanup. Without either option, the CLI selects the personal board; use demo or an explicit disposable path for development.

## AI clients

MCP uses standard input/output, with no network listener or independent background service. Its lifetime belongs to the client: closing stdin terminates it. It runs with the invoking user's filesystem permissions.

The connected client can access returned records and may send them to a remote model according to its own settings. `--read-only` hides and rejects the mutation tool but does not redact responses. Use `--demo` when evaluating an unfamiliar client. Review transcripts and exports before sharing them.

## Public distribution

Only application code, documentation, the icon, fictional examples and tests belong in this repository. Personal boards, imports, exports, credentials, logs, debug symbols and caches do not. Public Git history starts with the sanitized release; earlier private commits are not included.

The automated audit checks common machine paths, private artifacts and credential formats. It complements manual review, not a guarantee of anonymity. Developer ID signatures intentionally identify the signer and Team ID. GitHub identifies the publishing account; commits use its GitHub-provided noreply address.
