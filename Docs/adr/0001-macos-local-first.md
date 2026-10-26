# ADR 0001: macOS-first local architecture

- Status: Accepted
- Date: 2026-08-28

## Context

The primary interaction is a wide, dense matrix requiring a large display, pointer precision and keyboard support. The initial user is in the Apple ecosystem and does not yet require collaboration or a shared server.

## Decision

Build a native SwiftUI macOS application with a local repository abstraction. Keep domain and application modules portable so iOS, widgets and CloudKit can be added later.

## Consequences

- The first release can feel native and work offline.
- A remote backend is not required for core value.
- Synchronisation and collaboration remain future adapters rather than implicit assumptions.
- Matrix interaction must be designed for macOS first and adapted—not merely shrunk—for iOS.
