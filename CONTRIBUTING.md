# Contributing

## Engineering rules

Use English for documentation and code comments. The Chinese README and localized UI resources are intentional exceptions. Keep screenshots and examples fictional; never include personal manuscript records, submission IDs, exports or local machine paths. See [privacy](Docs/PRIVACY.md) and [release engineering](Docs/RELEASING.md).

1. Domain types must not import SwiftUI, AppKit, persistence frameworks, or networking libraries.
2. All state changes must pass through `BoardCommandService`; views never edit persisted models directly.
3. A target-plan change must never create a submission event.
4. Historical events are append-only. Corrections are explicit replacement operations with an audit reason, not silent mutation.
5. Persist journal identity by internal UUID and snapshot the display name on every submission event.
6. New UI colors, spacing, typography, and shapes belong in `ManuscriptDesignSystem`.
7. Every domain invariant requires a focused unit test.

## Workflow

```bash
make generate
make test
make build
```

Keep commits focused. Update `CHANGELOG.md` for user-visible changes and add an ADR when a decision changes a durable architectural boundary.

## Definition of done

- domain behavior has tests;
- macOS target builds without warnings introduced by the change;
- empty, dense, and long-title UI states remain usable;
- documentation reflects contract or persistence changes;
- no UI-only shortcut bypasses the command layer.
