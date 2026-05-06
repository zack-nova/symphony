# Symphony Service

This context defines the language for Symphony's issue-tracker-neutral orchestration model.

## Language

**Tracker Adapter**:
A backend-specific boundary that converts issue tracker facts into Symphony's normalized issue model.
_Avoid_: Tracker integration, provider implementation

**Tracker Options**:
Adapter-specific configuration nested under the selected tracker kind.
_Avoid_: Tracker config, backend fields

**State Set**:
A named list of tracker state values that Symphony uses for orchestration decisions.
_Avoid_: Lifecycle role, status group

**Tracker Capability**:
An adapter-declared operation that may or may not be available for a selected tracker backend.
_Avoid_: Feature flag, permission

## Relationships

- A **Tracker Adapter** belongs to exactly one tracker backend.
- **Tracker Options** are interpreted by exactly one **Tracker Adapter**.
- A **State Set** uses tracker-native state values during the first tracker-neutralization phase.
- A **Tracker Adapter** declares **Tracker Capabilities** so callers can distinguish unsupported operations from runtime failures.

## Example Dialogue

> **Dev:** "Should GitHub labels become lifecycle roles immediately?"
> **Domain expert:** "No. In the first phase, the GitHub **Tracker Adapter** returns normalized issues, and Symphony still uses configured **State Sets** for dispatch and terminal cleanup."

## Flagged Ambiguities

- "tracker config" was used for both common orchestration settings and backend-specific settings; resolved by using **State Set** for common active/terminal lists and **Tracker Options** for adapter-specific fields.
- "read adapter" and "write adapter" were considered as separate boundaries; deferred in favor of a single **Tracker Adapter** that declares **Tracker Capabilities**.
