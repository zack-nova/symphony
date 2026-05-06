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

**Tracker Scope**:
The configured boundary that determines which tracker issues Symphony is allowed to manage.
_Avoid_: Issue filter, project filter

**Label State**:
A tracker state expressed by exactly one issue label with the `state:` prefix.
_Avoid_: Status label, lifecycle label

**Scope Label**:
A single tracker label with the `project:` prefix that selects which issues a label-based tracker adapter manages.
_Avoid_: GitHub Project, ProjectV2 item

**Tracker Issue Identity**:
The stable identifier Symphony uses to claim, reconcile, and route one normalized tracker issue.
_Avoid_: Issue number, database ID

## Relationships

- A **Tracker Adapter** belongs to exactly one tracker backend.
- **Tracker Options** are interpreted by exactly one **Tracker Adapter**.
- A **State Set** uses tracker-native state values during the first tracker-neutralization phase.
- A **Tracker Adapter** declares **Tracker Capabilities** so callers can distinguish unsupported operations from runtime failures.
- A **Tracker Scope** must be explicit when an adapter could otherwise see unrelated tracker issues.
- A **Label State** provides the single tracker-native state value for an issue when the selected **Tracker Adapter** uses labels for state.
- A **Scope Label** limits which issues a label-based **Tracker Adapter** treats as part of Symphony's orchestration scope.
- A **State Set** stores complete tracker-native values, so GitHub label-based states include the full `state:` prefix.
- A **Label State** error inside **Tracker Scope** is a tracker contract violation, not a reason to silently skip an issue.
- Updating a **Label State** replaces only the existing `state:` label and preserves **Scope Labels** and ordinary labels.
- The first GitHub **Tracker Scope** label form uses one `project:` **Scope Label** rather than multi-label matching.
- A tracker assignee is an optional routing condition inside **Tracker Scope**, not part of **Tracker Scope** itself.
- GitHub open/closed state is synchronized from **Label State** updates but is not the source of Symphony's normalized issue state.
- A **Label State** may exist outside the configured active and terminal **State Sets**; those sets control orchestration, not the complete state vocabulary.
- Non-state labels such as `type:` or `area:` labels remain ordinary tracker labels in the first GitHub slice; Orbit contract validation is deferred.
- A GitHub **Tracker Issue Identity** uses `owner/repo#number` for both the normalized issue ID and human-readable identifier in the first GitHub slice.
- The first GitHub slice supports one configured repository; multi-repository polling is deferred.
- Tracker authentication uses the common `api_key` **Tracker Option**; the default environment variable is adapter-specific.
- The first GitHub slice supports comment creation and **Label State** updates, but not issue section editing or review artifact management.
- Candidate polling validates **Label State** only for open issues inside **Tracker Scope** before filtering by active **State Set**.
- Terminal-state lookup returns matching issues inside **Tracker Scope** without auditing every scoped issue.
- Running issue reconciliation validates **Label State** for the specific issues Symphony is already managing.
- GitHub supports an optional `endpoint` **Tracker Option** for Enterprise API hosts; its default endpoint is adapter-specific.
- Label-based tracker adapters match label prefixes case-insensitively and normalize label-derived state values to lowercase.
- A **Label State** update target must include the complete `state:` prefix, even when the target is outside active or terminal **State Sets**.

## Example Dialogue

> **Dev:** "Should GitHub labels become lifecycle roles immediately?"
> **Domain expert:** "No. In the first phase, the GitHub **Tracker Adapter** returns normalized issues, and Symphony still uses configured **State Sets** for dispatch and terminal cleanup."

## Flagged Ambiguities

- "tracker config" was used for both common orchestration settings and backend-specific settings; resolved by using **State Set** for common active/terminal lists and **Tracker Options** for adapter-specific fields.
- "read adapter" and "write adapter" were considered as separate boundaries; deferred in favor of a single **Tracker Adapter** that declares **Tracker Capabilities**.
- GitHub issue labels can contain multiple values, but a **Label State** must be unique per issue so Symphony can produce one normalized tracker issue state.
- "project" in the first GitHub slice means a `project:` **Scope Label**, not a GitHub Projects v2 item; GitHub Projects v2 support is deferred.
