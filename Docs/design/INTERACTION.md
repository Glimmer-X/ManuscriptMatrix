# Interaction model

## Matrix grammar

- Rows are journals in global rank order.
- Columns are manuscripts.
- The journal identity column is horizontally frozen; manuscript columns scroll as one shared horizontal plane.
- Journal rows and manuscript cells share one vertical scroll position, so rank and cell alignment never diverge.
- The top preparation row contains manuscripts with no live submission and
  shows five coarse stages from grey `已收录` through jade `完成`.
- A solid card is a live submission.
- A coloured dashed card is a future target and carries its priority number.
- A subdued trace is a completed event at that journal.

One cell may contain a live card plus older traces when a manuscript returns to the same journal.

## Semantic zoom

The matrix has two persistent density levels rather than mechanically scaling
the same typography:

- **Detailed** keeps full manuscript headers, journal metrics, elapsed time and
  card labels.
- **Overview** reduces row and column geometry, keeps only manuscript short
  titles and journal names, replaces publisher wordmarks with brand-colour
  dots, and renders cell state as a label-free colour mark.

The frozen journal column, row alignment, hit targets, popovers and VoiceOver
descriptions remain available in both levels. Users can switch from the toolbar,
with `⌘−` / `⌘+`, or by pinching on the matrix. The transition uses one short
spring so geometry and semantic content change as a single motion.

## Primary interaction

Version one is click-first and does not require drag and drop.

### Empty cell

Clicking opens actions to set a target priority, record an actual submission, mark the journal as excluded, or cancel.

### Target cell

Clicking allows reprioritisation, removal or conversion into a real submission. Conversion always shows a concise confirmation because it starts the elapsed-time clock and creates history.

### Live cell

Clicking opens the manuscript card with status actions: major revision, minor revision, reject and resubmit, resubmitted, rejected, accepted and withdrawn.

### Historical cell

Clicking shows absolute dates, duration in the journal and all events for that manuscript/journal pair.

### Management views

The sidebar switches between the matrix and focused lists for manuscripts, journals, declared relationships and activity. Portfolio counters are also matrix filters. `未完成` includes every pre-completion preparation stage, while `准备提交` requires `readyToSubmit`, no live submission and no latest rejection. Journal metadata, manuscript labels and preparation stage are editable without changing stable identity. Archiving is allowed only when no live submission would be hidden.

### History correction

An incorrectly entered event is marked void with a required reason. It remains visible as a corrected audit record, while current status is re-projected from the remaining valid events.

## Application settings

The standard macOS application menu exposes **Settings…**. Appearance can
follow the system or force Light/Dark mode, and the interface language can
switch between Simplified Chinese and English without changing journal names,
manuscript titles, tags, notes or other user-authored content. Both preferences
persist in `UserDefaults` and update open scenes immediately.

## Time hierarchy

- Live elapsed time is the strongest numeric element: `47d`.
- Current decision state is secondary: `Major revision`.
- Historical relative time is smaller: `Rejected 76d ago`.
- Exact timestamps and total duration live in the expanded inspector.

## Safety

- Target edits happen immediately and are undoable.
- Real-world event recording uses confirmation or a clearly labelled action.
- The command service returns a human-readable receipt.
- AI-initiated multi-step changes should present a preview before commit.
