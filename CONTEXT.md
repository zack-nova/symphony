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

**Symphony Setup Skill**:
An operator-side Codex skill that helps a user configure and run Symphony for a target repository without requiring the target repository to install that skill.
_Avoid_: Repo-local Symphony skill, target repository skill

**Setup Interview**:
A guided configuration dialogue where missing Symphony setup facts are gathered from the operator after repository inspection.
_Avoid_: Setup wizard, config questionnaire

**Repository Setup Contract**:
The shallow, setup-relevant facts that a target repository exposes for configuring Symphony.
_Avoid_: Repository requirements, all project rules

**Setup Workspace**:
The operator-controlled workspace where a **Symphony Setup Skill** stores generated configuration, run instructions, and evidence for a target repository.
_Avoid_: Target repository, temporary scratch space

**Setup Completion**:
The point where Symphony configuration has been generated, validated, started, and explained well enough for the operator to run a test issue.
_Avoid_: Task completion, successful agent delivery

**Agent Runtime Readiness**:
The preflight confidence that Codex app-server, sandbox policy, workspace access, credentials, and tracker permissions are sufficient for Symphony to run agents.
_Avoid_: Troubleshooting, health check

**Readiness Remediation**:
The response to an **Agent Runtime Readiness** failure, classified by whether the setup skill may fix it automatically, needs operator confirmation, or must report a blocker.
_Avoid_: Auto-fix, troubleshooting step

**Protocol Preflight**:
The required **Agent Runtime Readiness** check that starts Codex app-server and completes a minimal session and turn.
_Avoid_: Version check, smoke app-server

**Capability Preflight**:
An **Agent Runtime Readiness** check for a specific live-run ability such as repository push, tracker writes, network access, or bootstrap dependency installation.
_Avoid_: Full task rehearsal, generic validation

**Setup Secret**:
A credential needed to configure or start Symphony that is referenced by environment variable rather than written into setup artifacts.
_Avoid_: Saved token, checked-in credential

**Tracker Preparation**:
The setup step that checks and optionally creates tracker metadata needed for Symphony orchestration.
_Avoid_: Tracker migration, label sync

**Symphony Runtime**:
The executable Symphony implementation that the setup process starts for a configured target repository.
_Avoid_: Installed service, local binary

**Setup Decision Point**:
A setup choice that changes tracker scope, orchestration state, credentials, runtime selection, or whether real agents run.
_Avoid_: Every setup step, routine inspection

**Smoke Mode**:
A setup run mode that validates Symphony configuration and dispatch safety without letting real agents work on existing target repository issues.
_Avoid_: Dry run, fake setup

**Live Mode**:
A setup run mode where Symphony starts real Codex agent sessions for issues inside the configured tracker scope.
_Avoid_: Production mode, normal mode

**Operator Handoff**:
The concise setup summary and collaboration instructions given to the operator after Symphony has been configured and started.
_Avoid_: Full runbook, setup report

**Operator Workflow Map**:
A state-flow explanation that shows how work moves through the configured tracker states and which states are handled by Symphony or by humans.
_Avoid_: Status list, label table

**Setup Override**:
An operator decision that intentionally replaces a repository-derived setup fact.
_Avoid_: User preference, manual tweak

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
- A **Symphony Setup Skill** may write harness configuration into a target repository, but the skill itself runs from the operator's Codex environment.
- A **Symphony Setup Skill** supports both GitHub Issues and Linear setup paths by inspecting the target repository, choosing a **Tracker Adapter**, and using a **Setup Interview** to collect missing **Tracker Options** and **State Sets**.
- A **Repository Setup Contract** is read from the shallowest authoritative repository sources first, such as `WORKFLOW.md`, agent instructions, harness metadata, and README setup guidance.
- **Label State**, Linear workflow states, and other tracker rules are part of a **Repository Setup Contract**, but they are not the whole contract.
- A **Symphony Setup Skill** writes generated setup artifacts into a **Setup Workspace** by default; writing those artifacts back into the target repository is optional and user-directed.
- **Setup Completion** requires a selected **Tracker Adapter**, required **Tracker Options**, configured **State Sets**, a runnable workflow file, a workspace bootstrap path, a started dashboard, and operator-facing test instructions.
- **Setup Completion** does not require Codex to complete a real target repository issue.
- **Setup Completion** requires **Agent Runtime Readiness** before entering **Live Mode**.
- **Agent Runtime Readiness** covers Codex executable discovery, app-server protocol compatibility, Codex auth, sandbox policy, workspace writability, repository trust warnings, setup secret propagation, tracker permissions, clone access, and bootstrap hook viability.
- **Agent Runtime Readiness** is a preflight gate, not an after-the-fact failure investigation.
- **Readiness Remediation** may automatically apply compatibility-safe configuration changes such as supported approval policy values, correct workspace writable roots, secret environment references, available dashboard ports, and missing setup directories.
- **Readiness Remediation** requires operator confirmation before expanding sandbox authority, trusting a project, changing tracker metadata, persisting credentials, or entering **Live Mode**.
- **Readiness Remediation** reports a blocker when required tools, auth, repository access, tracker permissions, or machine runtime dependencies are missing and cannot be fixed without external operator action.
- **Protocol Preflight** is required for **Agent Runtime Readiness** and must exercise a real Codex app-server session rather than only checking `codex --version`.
- **Capability Preflight** is required only for abilities the configured **Live Mode** expects agents to use.
- **Capability Preflight** should validate permissions and sandbox access without performing a full real target issue.
- A **Symphony Setup Skill** references **Setup Secrets** in generated workflow files and injects their values only into the running Symphony process when available.
- A **Setup Secret** must not be written into the target repository, the **Setup Workspace** artifacts, or shell startup files by default.
- **Tracker Preparation** inspects required state metadata before changing it and applies tracker mutations only after operator confirmation.
- GitHub **Tracker Preparation** may create missing labels after confirmation, while Linear **Tracker Preparation** prefers reading existing workflow states and asking the operator to resolve missing states.
- **Tracker Preparation** does not automatically relabel existing issues into Symphony's **Tracker Scope**.
- A **Symphony Setup Skill** discovers the **Symphony Runtime** from **Setup Workspace** instructions first, then from an installed executable, then from a local Symphony source checkout.
- A missing **Symphony Runtime** is a setup blocker that should be reported with the expected discovery locations.
- A **Setup Interview** asks only at **Setup Decision Points** and performs low-risk repository and environment inspection without prompting.
- **Setup Decision Points** include tracker backend selection, **Tracker Scope**, **State Sets**, **Tracker Preparation** mutations, missing **Setup Secrets**, missing **Symphony Runtime**, and whether existing issues may be claimed by real agents.
- A **Symphony Setup Skill** starts in **Smoke Mode** by default and enters **Live Mode** only after operator confirmation.
- **Smoke Mode** may validate tracker access, generated workflow configuration, dashboard startup, and a dedicated test issue path.
- **Live Mode** requires explicit confirmation that the selected **Tracker Scope** and **State Sets** may be used by real agents.
- An **Operator Handoff** describes the key configured values and how the operator should work with Symphony after setup.
- An **Operator Handoff** is concise because the **Symphony Setup Skill** is responsible for configuring and starting Symphony, not asking the operator to execute the setup manually.
- An **Operator Handoff** includes an **Operator Workflow Map** rather than only listing configured states.
- An **Operator Workflow Map** distinguishes Symphony-managed active states from human-managed review, decision, blocked, and terminal states.
- An **Operator Handoff** includes **Agent Runtime Readiness** results, including Codex executable, Codex version, approval policy, sandbox summary, **Protocol Preflight** result, **Capability Preflight** results, trust warnings, blockers, and applied **Readiness Remediation**.
- A **Symphony Setup Skill** confirms a **State Prompt** for each Symphony-managed state in the configured active **State Set** when repository evidence does not already define it.
- A **Symphony Setup Skill** does not invent fallback state names or initialize a default workflow; missing state flow facts are resolved through the **Setup Interview** or **Setup Workspace** guidance.
- Repository evidence provides setup defaults, but a **Setup Override** is the final authority when the operator knowingly chooses a different configuration.
- A **Setup Override** must record the repository evidence it replaces, the operator's chosen value, and the affected generated configuration.

## Example Dialogue

> **Dev:** "Should GitHub labels become lifecycle roles immediately?"
> **Domain expert:** "No. In the first phase, the GitHub **Tracker Adapter** returns normalized issues, and Symphony still uses configured **State Sets** for dispatch and terminal cleanup."

> **Dev:** "Should the target repository install the **Symphony Setup Skill** before Symphony can run?"
> **Domain expert:** "No. The **Symphony Setup Skill** runs operator-side; the target repository only receives the configuration and instructions needed for Symphony runs."

> **Dev:** "Can the **Symphony Setup Skill** assume GitHub Issues because the user gave a GitHub URL?"
> **Domain expert:** "No. The repository URL identifies source code; the **Setup Interview** still determines whether the run should use the GitHub or Linear **Tracker Adapter**."

> **Dev:** "Should the **Symphony Setup Skill** treat every repository instruction as a Symphony requirement?"
> **Domain expert:** "No. It extracts the **Repository Setup Contract**: the shallow setup facts needed to configure and run Symphony, not every project rule."

> **Dev:** "Should generated Symphony setup files be committed into the target repository immediately?"
> **Domain expert:** "No. The default artifact location is the **Setup Workspace**; repository writes are optional."

> **Dev:** "Is setup complete only after an agent finishes a real issue?"
> **Domain expert:** "No. **Setup Completion** means the operator can create or select a test issue and observe Symphony handling it; delivery success is a separate validation."

> **Dev:** "Can setup enter **Live Mode** if Codex app-server has not been tested?"
> **Domain expert:** "No. **Agent Runtime Readiness** must pass first, including Codex protocol, sandbox, credentials, and permissions."

> **Dev:** "Can setup silently switch to `danger-full-access` when sandbox blocks a command?"
> **Domain expert:** "No. That is **Readiness Remediation** requiring operator confirmation because it expands runtime authority."

> **Dev:** "Is `codex --version` enough to prove agents can run?"
> **Domain expert:** "No. **Protocol Preflight** must start Codex app-server and complete a minimal turn; **Capability Preflight** then checks configured live-run abilities."

> **Dev:** "Should the generated workflow include the user's GitHub or Linear token value?"
> **Domain expert:** "No. Tokens are **Setup Secrets**; the workflow should reference environment variables such as `$GITHUB_TOKEN` or `$LINEAR_API_KEY`."

> **Dev:** "Can setup silently create labels or move issues so Symphony starts running?"
> **Domain expert:** "No. **Tracker Preparation** can propose metadata changes, but tracker mutations require operator confirmation."

> **Dev:** "Should the **Symphony Setup Skill** install Symphony if it cannot find an executable?"
> **Domain expert:** "No. It should first follow **Setup Workspace** instructions and discovery order; missing runtime is a blocker to report."

> **Dev:** "Should setup ask before reading repository instructions or checking labels?"
> **Domain expert:** "No. The **Setup Interview** asks at **Setup Decision Points**; routine inspection should proceed without interruption."

> **Dev:** "Can setup immediately point Symphony at existing ready issues?"
> **Domain expert:** "No. Start in **Smoke Mode**; **Live Mode** requires explicit confirmation."

> **Dev:** "Should the final answer be a long runbook for the operator to follow?"
> **Domain expert:** "No. After setup runs, provide an **Operator Handoff**: key configuration and how to collaborate with Symphony."

> **Dev:** "Should runtime readiness details stay hidden unless something fails?"
> **Domain expert:** "No. The **Operator Handoff** should summarize **Agent Runtime Readiness** so future failures can be compared against setup evidence."

> **Dev:** "Is it enough to tell the operator which labels exist?"
> **Domain expert:** "No. Provide an **Operator Workflow Map** that explains state flow and ownership."

> **Dev:** "Can setup invent a default state flow when the repository is silent?"
> **Domain expert:** "No. The **Symphony Setup Skill** should use repository evidence first and ask through the **Setup Interview** when state flow or **State Prompts** are missing."

> **Dev:** "What if the repository implies Linear but the operator wants GitHub Issues?"
> **Domain expert:** "That is a **Setup Override**. Use the operator's choice, but record the conflict and generated configuration impact."

## Flagged Ambiguities

- "tracker config" was used for both common orchestration settings and backend-specific settings; resolved by using **State Set** for common active/terminal lists and **Tracker Options** for adapter-specific fields.
- "read adapter" and "write adapter" were considered as separate boundaries; deferred in favor of a single **Tracker Adapter** that declares **Tracker Capabilities**.
- GitHub issue labels can contain multiple values, but a **Label State** must be unique per issue so Symphony can produce one normalized tracker issue state.
- "project" in the first GitHub slice means a `project:` **Scope Label**, not a GitHub Projects v2 item; GitHub Projects v2 support is deferred.
- "different label prompt" was clarified to mean a **State Prompt** selected from the active tracker state, not arbitrary issue labels.
- "turn-time state prompt injection" was clarified as an **Active State Guidance Refresh**, not a restart of the current agent run.
- "multiple state prompt injections" was resolved with latest-state-wins pending **Active State Guidance Refresh** delivery.
- "skill" can mean a repo-local agent skill or an operator-side helper; resolved: **Symphony Setup Skill** means the operator-side helper that configures and starts Symphony for a target repository.
- A repository URL alone does not select the tracker backend; the **Symphony Setup Skill** must support GitHub Issues and Linear and use a **Setup Interview** when repository inspection cannot determine the correct **Tracker Adapter**.
- "repository requirements" is too broad for setup; resolved: **Repository Setup Contract** means only the shallow facts needed to configure and run Symphony, while tracker state rules are one subset of those facts.
- "where configuration lives" was ambiguous; resolved: generated setup artifacts live in the **Setup Workspace** by default, not automatically in the target repository.
- "configuration complete" was clarified as **Setup Completion**, not successful completion of a real agent task.
- Codex, sandbox, credential propagation, and tracker permission checks were clarified as **Agent Runtime Readiness**, a required setup gate rather than optional troubleshooting.
- **Agent Runtime Readiness** failures use **Readiness Remediation**: safe compatibility changes can be automatic, authority expansion requires confirmation, and missing external access is a blocker.
- **Agent Runtime Readiness** uses **Protocol Preflight** for required Codex app-server proof and **Capability Preflight** for live-run-specific permissions.
- Tracker credentials are **Setup Secrets**; they are checked for availability and injected at runtime, but not persisted into generated artifacts by default.
- Tracker metadata changes are **Tracker Preparation**, not implicit setup; creation or modification requires operator confirmation.
- The **Symphony Runtime** location comes from **Setup Workspace** instructions when present; automatic discovery is fallback behavior.
- The **Setup Interview** is not a step-by-step wizard; it asks only when a **Setup Decision Point** cannot be resolved from repository or environment evidence.
- "running Symphony" can mean **Smoke Mode** or **Live Mode**; resolved: setup defaults to **Smoke Mode** and requires confirmation before **Live Mode**.
- The final user-facing artifact is an **Operator Handoff**, not a manual setup checklist, because setup work is performed by the skill.
- Runtime readiness evidence belongs in the **Operator Handoff**, but as a concise summary rather than full logs.
- "state documentation" should be an **Operator Workflow Map**, not a flat status list, so operators know which states Symphony handles and which require human action.
- Built-in fallback state initialization was rejected; state flow and **State Prompts** come from repository evidence, **Setup Workspace** guidance, or operator answers.
- **State Prompts** are part of setup for Symphony-managed states unless the target repository intentionally uses only the workflow body prompt.
- Repository evidence is not absolute; an explicit **Setup Override** wins but must be documented.
