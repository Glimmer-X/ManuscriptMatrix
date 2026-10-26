# Agent interface

## Principle

An AI agent is another client of the application layer, not a privileged database editor. UI and agent operations share validation, event generation, persistence and audit receipts.

## Command vocabulary

- `manuscript.create`
- `manuscript.update`
- `manuscript.position.set`
- `manuscript.readiness.set`
- `manuscript.archive.set`
- `manuscript.delete`
- `journal.create`
- `journal.rename`
- `journal.rank.set`
- `journal.metadata.update`
- `journal.archive.set`
- `journal.delete`
- `target.set`
- `target.remove`
- `submission.record`
- `submission.status.record`
- `submission.event.amend`
- `submission.event.void`
- `relationship.create`
- `relationship.update`
- `relationship.remove`

The canonical envelope is documented in `Contracts/agent-command.schema.json`.

## Local console

### Installed app

The signed release includes a universal executable at:

```text
/Applications/Manuscript Matrix.app/Contents/Helpers/manuscript-matrix-agent
```

No additional runtime is required. Replace the path if the app is installed elsewhere. Quote it in a shell because the app name contains spaces; an MCP client's `command` field takes the path as a single JSON string without embedded shell quotes.

For clients using the `mcpServers` configuration format:

```json
{
  "mcpServers": {
    "manuscript-matrix": {
      "command": "/Applications/Manuscript Matrix.app/Contents/Helpers/manuscript-matrix-agent",
      "args": ["--read-only", "mcp"]
    }
  }
}
```

Client configuration locations differ; use your client's MCP settings. Start with `--demo` instead of `--read-only` to try fictional data. Demo writes last only for that server process. Remove `--read-only` to enable updates to the selected persistent board. Read access may return private records to the AI client; see [privacy](../PRIVACY.md).

### Data selection and read-only access

Options can appear before or after the command:

```bash
AGENT='/Applications/Manuscript Matrix.app/Contents/Helpers/manuscript-matrix-agent'
"$AGENT" --demo board
"$AGENT" --demo mcp
"$AGENT" --read-only mcp
"$AGENT" --board "$PWD/build/example-board.json" board
```

- No data option: the same Application Support board used by the app.
- `--board FILE`: a separate explicit JSON file. Missing files read as empty; validated writes create them. This does not change the app's data location.
- `--demo`: an in-memory fictional board with no persistent writes. Cannot be combined with `--board`.
- `--read-only`: rejects `apply`, hides the MCP mutation tool, and rejects direct calls to that tool. Read tools still return unredacted records.
- `path`: prints the selected board location, and fails in demo mode because there is no file.

The server uses stdin/stdout until EOF; the client owns and stops it. It has no daemon installation, network transport, authentication layer, or HTTP endpoint. Do not put its stdout through a shell greeting, progress logger or other filter that breaks JSON-RPC. Restart a client-managed server after replacing the installed app.

### Source checkout

The local bridge supports direct JSON-in/JSON-out commands and an MCP stdio server:

```bash
swift run --disable-sandbox --package-path Packages/ManuscriptKit \
  manuscript-matrix-agent board

swift run --disable-sandbox --package-path Packages/ManuscriptKit \
  manuscript-matrix-agent apply < command.json

swift run --disable-sandbox --package-path Packages/ManuscriptKit \
  manuscript-matrix-agent mcp
```

It shares the application-support board file with the macOS app and executes the
same typed commands through `BoardMutationExecutor`; it never performs direct
text edits on stored JSON. Saves use a cross-process lock and optimistic
snapshot comparison. On a concurrent change, the command is retried against the
latest board instead of overwriting it. The running macOS app watches the
repository and normally reflects a successful MCP mutation within a fraction of
a second, without relaunching.

## MCP tools

- `matrix_board_get`: complete board and stable identifiers;
- `matrix_board_summary`: compact current status and elapsed-time projection;
- `matrix_command_catalog`: exact payload fields for every supported operation;
- `matrix_command_apply`: one typed version-1 mutation command.

The server uses newline-delimited JSON-RPC over standard input/output. It accepts `initialize`, `ping`, `tools/list` and `tools/call`, while also permitting tool discovery without a mandatory initialization round trip. Successful calls return both text content and `structuredContent`; validation failures are tool errors and do not modify the board.

The server identifies as `manuscript-matrix` version `0.9.0`. It supports the `2025-11-25` protocol dialect for its stdio tool surface. To inspect the real tool definitions without reading any personal data:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"example","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | "$AGENT" --demo mcp
```

Command IDs appear in receipts for correlation; they do not provide persistent request deduplication. Read current state before retrying a write whose result was lost. The `journal.metadata.update` command replaces metadata: preserve fields you intend to retain.

The command surface covers complete CRUD for journal and manuscript entities. Journal creation and metadata replacement include name, rank, IF, subject category, decision days, ISSN/eISSN, tags and an arbitrary list of partition records. Permanent deletion requires `confirmPermanentDeletion: true` and cascades through dependent board records.

Manuscripts carry a preparation stage independent of submission history. The
ordered values are `incomplete` (registered/not started), `experimenting`,
`conceptualizing`, `writing`, and `readyToSubmit` (complete). Use
`manuscript.readiness.set` with an optional `occurredAt` timestamp to change the
stage. New agent-created manuscripts default to `incomplete`; schema-v1
manuscripts with no saved readiness decode as `readyToSubmit` for backward
compatibility.

Manuscript columns have a persistent one-based display position. Use
`manuscript.position.set` with `manuscriptId` and `position`; all visible
positions are normalized after the move. Boards created before this field was
introduced retain their chronological column order until the first explicit
move establishes positions.

Every creation and submission command accepts an explicit ISO-8601 event time, so agents can backfill historical records. Use `submission.event.amend` to correct an existing event's `occurredAt` or note: the previous values, reason and amendment time remain embedded in the event's audit history.

Partition payload example:

```json
{
  "scheme": "CAS",
  "year": 2025,
  "value": "1区",
  "category": "Computer Science"
}
```

Partition values are closed enums and runtime validation rejects custom text:
`JCR` uses `Q1`–`Q4`, `CCF` uses `A`–`C`, and `CAS`/`新锐` use `1区`–`4区`.
Omit a partition record when the value is unknown; never send placeholders such
as `待核对`, `未收录`, `-`, or `—`. The legacy top-level `quartile` payload is
accepted only for backward compatibility; new clients use `partitions`.

## Mutation workflow

1. Parse the user's natural-language statement into one or more typed commands.
2. Resolve manuscript and journal names to stable UUIDs; ask when resolution is ambiguous.
3. Produce a preview describing exact changes when the instruction is ambiguous or consequential.
4. Apply commands only after the user's authority is clear.
5. Return a receipt with command ID, timestamp and affected entities.

## Example

User statement:

> Paper A was rejected by Journal Alpha today. Make Journal Beta its first target.

Resulting operations:

```json
[
  {
    "type": "submission.status.record",
    "payload": {
      "manuscriptId": "…",
      "journalId": "…",
      "status": "rejected",
      "occurredAt": "2026-08-28T09:00:00Z"
    }
  },
  {
    "type": "target.set",
    "payload": {
      "manuscriptId": "…",
      "journalId": "…",
      "priority": 1
    }
  }
]
```

## Guardrails

- never infer that moving or targeting means submitted;
- never infer manuscript relationships from PDFs as authoritative facts;
- never match journals only by mutable display name when more than one candidate exists;
- never rewrite past journal-name snapshots after a rename;
- never delete an incorrect event: amend its date/note with `submission.event.amend`, or use `submission.event.void` when the event itself never happened;
- never archive a manuscript or journal while it has a live submission;
- return the mutation receipt for every write.
