# Product scope

## Product statement

Manuscript Matrix is a strategic submission board for a researcher managing several manuscripts against a ranked journal landscape.

The primary question is not “what work remains inside this paper?” It is “where is this manuscript now, how long has it been there, what happened before, and where could it go next?”

## Core concepts

- **Journal ladder:** one globally ordered set of journals.
- **Manuscript lane:** one stable column per manuscript.
- **Live submission:** the one journal currently handling a manuscript.
- **Target plan:** editable, per-manuscript first/second/third choices. Planning never implies submission.
- **Historical trace:** the immutable residue left when a live submission receives a decision or is withdrawn.
- **Relationship:** a user-authored statement connecting two manuscripts for strategic reasoning.

## In scope for the first milestone

- create manuscripts and journals;
- edit, archive, restore and explicitly delete manuscripts and journals;
- rename a journal without changing its identity;
- assign per-manuscript target priorities;
- record submission, major revision, minor revision, reject-and-resubmit, rejection, acceptance and withdrawal;
- retain the full submission history while measuring current elapsed time from the latest submission or revision action;
- calculate elapsed and relative time;
- leave historical traces in matrix cells;
- connect two manuscripts with a directional natural-language statement;
- expose every mutation through documented application commands.
- browse dedicated manuscript, journal, relationship and activity views;
- import and export validated local board backups;
- expose read and mutation tools to trusted local AI clients over MCP stdio.
- store multiple simultaneous journal classifications, including annual JCR, CAS and other ranking systems.

## Explicitly out of scope

- experiment, writing or revision task management;
- manuscript content editing;
- co-author workflow and permissions;
- automatic journal submission;
- automatic interpretation of manuscript relationships;
- bibliographic reference management;
- automatic Impact Factor or quartile ingestion in the first milestone.

PDF files may later be attached as optional AI-analysis inputs. They are not the source of truth for board state.

## Product principles

1. **Strategy is visible.** Current position, history and future targets coexist in one matrix.
2. **Planning is reversible; history is durable.** Moving a target marker is harmless. Recording a real event is deliberate.
3. **Identity outlives names.** Journal and manuscript UUIDs are permanent.
4. **The researcher is authoritative.** AI may operate and analyse, but declared relationships and recorded decisions come from the user.
5. **Density without noise.** Collapsed cells show enough context to scan; details appear on demand.
