# Architecture

## System shape

The first release is a local-first macOS application. It uses a modular monorepo so iOS, widgets, CloudKit sync and a local agent service can be added without rewriting domain rules.

```text
┌──────────────────────────────────────────────────────────┐
│ macOS App / future iOS and widgets                       │
├──────────────────────────────────────────────────────────┤
│ MatrixFeature                 ManuscriptDesignSystem     │
├──────────────────────────────────────────────────────────┤
│ ManuscriptApplication: commands, validation, projections │
├──────────────────────────────────────────────────────────┤
│ ManuscriptDomain: identities, events, entities           │
├───────────────────────────────┬──────────────────────────┤
│ Local JSON repository (now)   │ Cloud/SQLite adapters    │
└───────────────────────────────┴──────────────────────────┘
                   ▲
                   │ same command boundary
          Local CLI / MCP AgentBridge
```

## Module responsibilities

### ManuscriptDomain

Foundation-only value types and pure projections. It knows nothing about UI, files, CloudKit, AI or AppKit.

### ManuscriptApplication

Owns use cases and invariants. `BoardMutationExecutor` is the shared write coordinator for the app and AgentBridge; `BoardCommandService` publishes its results to SwiftUI and manages undo. The executor conditionally saves against the snapshot it read and retries a command on the latest snapshot when another process wins the write race.

### ManuscriptInfrastructure

Implements repository protocols. The initial adapter uses atomically written JSON, a cross-process advisory lock, optimistic snapshot comparison and a debounced directory-change stream. The macOS app therefore sees external MCP writes without a restart. A future SQLite/CloudKit adapter can replace it without changing views or commands.

### ManuscriptDesignSystem

Typography, spacing, shape and semantic color tokens shared by macOS, iOS and widgets.

### MatrixFeature

SwiftUI presentation and interaction. It renders projections and sends commands; it does not construct events directly.

### AgentBridge

A local JSON command console and MCP stdio server that maps structured agent tool calls onto `BoardReducer` and the repository abstraction. It never edits persistence files as unvalidated text.

## Data flow

```text
Click or agent request
        ↓
validated BoardCommand
        ↓
pure domain mutation + appended event
        ↓
atomic repository save
        ↓
cross-process change stream
        ↓
published BoardSnapshot
        ↓
matrix projection refresh
```

App and agent processes share one file and never maintain independent caches as
sources of truth. UI saves that trigger the file watcher are ignored when the
round-tripped snapshot equals the already-published board. A genuinely external
snapshot clears stale undo history before publication, preventing undo from
overwriting changes that arrived from another process.

## Evolution path

1. JSON repository for transparent local development.
2. SQLite/SwiftData adapter once migrations and querying justify it.
3. CloudKit synchronization with stable UUIDs and event conflict policy.
4. Read-only widget projections.
5. Optional authenticated network transport if remote-agent access is ever required. The current MCP server is local stdio only.

The architecture avoids committing to a remote backend before multi-user requirements exist. “Backend” currently means the application and persistence layers behind the UI; “service side” is an explicit boundary, not an always-running server.
