# ADR 0002: Commands for writes, events for history

- Status: Accepted
- Date: 2026-08-28

## Context

The board must distinguish harmless target planning from real submission history and must be controllable by both UI and AI without divergent behavior.

## Decision

All mutations pass through typed application commands. Real-world submission changes append immutable events; editable planning choices remain ordinary state. Both produce mutation receipts.

## Consequences

- Accidental drag or layout changes cannot fabricate history.
- AI can use the same validated operations as the UI.
- Current state is a projection and can be tested independently.
- Event corrections require explicit amend or void commands that retain an audit record.
