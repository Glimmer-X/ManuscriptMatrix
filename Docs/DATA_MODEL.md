# Data model

## Durable entities

### Journal

- permanent internal UUID;
- current display name;
- ranked position in the global journal ladder;
- optional metrics and research-area tags;
- zero or more partition records, each with its own scheme, optional year, value and subject category;
- ordered name-history records with effective dates.

ISSN and eISSN are attributes, not primary keys. A rename keeps the UUID. A split creates new journal identities with predecessor relationships in a later schema version.

`JournalPartition` is deliberately repeatable. One journal can therefore hold `JCR 2025 Q1`, `CAS 2024 1区`, `CAS 2025 2区` and a separate `新锐` classification at the same time. The old single `quartile` field remains only for schema-v1 compatibility and is migrated into a JCR record when older data is read.

Partition systems and grades use a finite vocabulary: JCR accepts Q1–Q4, CCF
accepts A–C, and CAS/新锐 accept 1区–4区. Missing knowledge is represented by
the absence of a partition record and rendered as `—`; prose placeholders such
as “待核对” or “未收录” are never stored as grades. Legacy `JCR 1区–4区` values
are normalized to Q1–Q4 during decoding, while ambiguous legacy values are
discarded rather than guessed.

### Manuscript

- permanent internal UUID;
- title and short label;
- optional persistent display position for matrix column ordering;
- optional tags;
- preparation stage (`incomplete`, `experimenting`, `conceptualizing`,
  `writing`, or `readyToSubmit`) and its effective timestamp;
- creation and archive timestamps.

Preparation remains a coarse manuscript-level signal rather than project-task
tracking. It records only the ordered phase: registered/not started,
experimenting, conceptualizing, writing, or complete. It stores no checklists,
experiment details, manuscript content or percentage estimates.

Older boards without explicit manuscript positions retain their chronological
column order. The first manual or agent-driven move assigns normalized positions
to every visible manuscript without changing creation timestamps.

### SubmissionEvent

An append-only fact connecting one manuscript and one journal. It stores both the journal UUID and the journal display-name snapshot at the time of the event.

Event kinds:

- submitted;
- resubmitted;
- major revision;
- minor revision;
- reject and resubmit;
- rejected;
- accepted;
- withdrawn.

### TargetChoice

An editable planning record connecting a manuscript and journal with a positive integer priority. Target changes do not create submission history.

### ManuscriptRelationship

One durable record with two endpoints, optional direction and a user-authored statement. Both manuscript views project the same record; inverse copies are never stored.

## Derived state

The live elapsed-time indicator starts at the latest submission, resubmission or revision event. Decision durations and prior event dates remain available independently; resetting the live indicator never removes historical records.

Current manuscript status and active journal are projections of the latest relevant submission events. Rejection and withdrawal end a submission, returning the manuscript to `awaitingSubmission`; acceptance is terminal unless explicitly reopened in a future version. Readiness is orthogonal to that event projection and never rewrites submission history.

The UI groups this projection into six mutually exclusive situations: incomplete, preparing submission, awaiting decision (`submitted` only), revision, rejected, and accepted. Every preparation stage before `readyToSubmit` belongs to incomplete; preparing submission requires both `awaitingSubmission` and `readyToSubmit`. A latest rejection remains rejected regardless of preparation stage. Activity summaries group non-voided events by their effective `occurredAt` date.

## Important invariants

- a manuscript has at most one live journal submission;
- a manuscript cannot target the same journal more than once;
- target priorities are unique and contiguous within a manuscript;
- a terminal accepted manuscript cannot be submitted again without an explicit future reopen command;
- historical journal-name snapshots never change when a journal is renamed;
- event dates and notes may be amended only with a reason; previous values remain in the event audit history;
- events that never happened are voided with a reason rather than deleted;
- relationships cannot connect a manuscript to itself.
- changing preparation stage never creates, removes or changes a submission event.

## Persistence envelope

Every saved board includes a schema version and last-modified timestamp. Migrations operate on the envelope before it becomes a domain snapshot.
