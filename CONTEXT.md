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

**State Prompt**:
A state-selected agent guidance block selected by the normalized tracker issue state.
_Avoid_: Label prompt, status prompt

**Active State Guidance Refresh**:
A state guidance update sent when a running issue moves from one active tracker state to another active tracker state.
_Avoid_: Prompt hot reload, state prompt retry

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
- A **State Prompt** is selected from `Tracker.Issue.state`, so GitHub and Linear use the same prompt-selection mechanism after tracker normalization.
- A **State Prompt** is configured with complete tracker-native state values and falls back to the workflow body prompt when no state-specific prompt matches.
- A **State Prompt** is appended to the workflow body prompt for the first agent turn rather than replacing the workflow body prompt.
- A **State Prompt** can also be sent through an **Active State Guidance Refresh** when a running issue changes between active **State Set** values.
- An **Active State Guidance Refresh** is only sent when the new active state has a matching **State Prompt**; otherwise Symphony only refreshes the running issue snapshot.
- An **Active State Guidance Refresh** does not apply when a running issue leaves active **State Set** values or enters terminal **State Set** values.
- An **Active State Guidance Refresh** should steer the current turn without interrupting it.
- If a current turn has already completed before **Active State Guidance Refresh** steering is attempted, the latest refresh guidance is delivered with the next continuation turn instead of failing the worker run.
- Failed **Active State Guidance Refresh** steering makes the worker run fail so retry can resume with required state guidance instead of allowing the agent to continue under stale guidance.
- Pending **Active State Guidance Refresh** delivery is appended to continuation guidance and does not resend the workflow body prompt.
- When multiple **Active State Guidance Refreshes** are detected before pending guidance is delivered, Symphony keeps only the latest state guidance.
- Each entry into an active state receives at most one delivered **Active State Guidance Refresh** unless the issue leaves and later re-enters that state.
- **Active State Guidance Refresh** delivery is based on observed tracker state transitions, regardless of whether the transition was made by a human or by the running agent.
- A **State Prompt** uses the same prompt template variables as the workflow body prompt.
- An **Active State Guidance Refresh** renders a **State Prompt** with the same template variables as the first agent turn, without transition-specific variables such as previous state.
- **State Prompt** keys match normalized tracker issue states using trim and lowercase semantics.
- A **State Prompt** configuration must not contain duplicate keys after state normalization.
- A **State Prompt** key must not be blank after trim, and its prompt guidance must be a non-empty string.
- A **State Prompt** key does not need to be a member of an active **State Set**, though it is only used when an issue is dispatched.
- When appended, a **State Prompt** is separated from the workflow body prompt with a fixed state guidance section heading.

## Example Dialogue

> **Dev:** "Should GitHub labels become lifecycle roles immediately?"
> **Domain expert:** "No. In the first phase, the GitHub **Tracker Adapter** returns normalized issues, and Symphony still uses configured **State Sets** for dispatch and terminal cleanup."

## Flagged Ambiguities

- "tracker config" was used for both common orchestration settings and backend-specific settings; resolved by using **State Set** for common active/terminal lists and **Tracker Options** for adapter-specific fields.
- "read adapter" and "write adapter" were considered as separate boundaries; deferred in favor of a single **Tracker Adapter** that declares **Tracker Capabilities**.
- GitHub issue labels can contain multiple values, but a **Label State** must be unique per issue so Symphony can produce one normalized tracker issue state.
- "project" in the first GitHub slice means a `project:` **Scope Label**, not a GitHub Projects v2 item; GitHub Projects v2 support is deferred.
- "different label prompt" was clarified to mean a **State Prompt** selected from the active tracker state, not arbitrary issue labels.
- "turn-time state prompt injection" was clarified as an **Active State Guidance Refresh**, not a restart of the current agent run.
- "multiple state prompt injections" was resolved with latest-state-wins pending **Active State Guidance Refresh** delivery.
