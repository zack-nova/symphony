# Symphony

This fork extends the Elixir implementation of
[OpenAI Symphony](https://github.com/openai/symphony) with tracker-neutral orchestration and
GitHub-oriented workflow support.

For the original Symphony introduction, demo, and language-agnostic service model, see the upstream
[README](https://github.com/openai/symphony/blob/main/README.md) and
[SPEC](https://github.com/openai/symphony/blob/main/SPEC.md). This README focuses on what this fork
changes.

> [!WARNING]
> This fork is prototype software for testing in trusted environments. It is not a hardened hosted
> service, and operators should review the configured tracker scope, workspace hooks, Codex sandbox
> policy, and credentials before running it against real issues.

## Fork changes

- **Tracker-neutral orchestration model**: shared tracker adapter contracts and normalized issue
  records so the orchestrator is no longer coupled to Linear.
- **GitHub label-state tracker**: `tracker.kind: github` support for GitHub Issues using an
  explicit tracker scope, `project:` scope labels, and exactly one `state:` label per managed issue.
- **GitHub issue writes**: comment creation and label-state updates through the GitHub adapter while
  preserving the existing Linear path.
- **State-specific prompts**: `agent.state_prompts` lets a workflow append guidance for particular
  tracker states such as `state:ready-for-dev`, `state:to-rework`, or `state:to-merge`.
- **Active state guidance refresh**: when a running issue moves between active states, Symphony can
  send the matching state prompt to the current Codex session instead of waiting for a fresh run.
- **Setup and readiness language**: documented concepts for setup workflows, smoke/live mode,
  runtime readiness, protocol preflight, capability preflight, setup secrets, and operator handoff.
- **Codex app-server hardening work**: safer defaults for approval and sandbox policy, explicit
  model command configuration, and additional regression coverage around app-server behavior.

## GitHub label-state workflow

The first GitHub slice intentionally uses GitHub Issues labels instead of GitHub Projects v2. A
managed issue must be inside the configured tracker scope and have exactly one `state:` label.

```yaml
tracker:
  kind: github
  active_states:
    - state:ready-for-dev
    - state:in-progress
    - state:to-rework
    - state:to-merge
  terminal_states:
    - state:merged
  options:
    repository: owner/repo
    api_key: $GITHUB_TOKEN
    scope:
      type: label
      label: project:orbit
    assignee: me
```

## State-specific guidance

Workflows can attach state-specific Codex guidance. The first matching prompt is appended to the
initial agent prompt, and active state transitions can refresh guidance for an already-running
session.

```yaml
agent:
  state_prompts:
    state:ready-for-dev: |
      Start fresh development work from the issue details.
    state:to-rework: |
      Address review feedback and preserve existing progress.
    state:to-merge: |
      Land the accepted change and report the merge result.
```

## Running this fork

Check out [elixir/README.md](elixir/README.md) for setup and runtime instructions for this
Elixir/OTP implementation. It documents Linear and GitHub tracker configuration, workspace hooks,
Codex app-server settings, the Phoenix observability dashboard, and live E2E testing.

You can also ask your favorite coding agent to help with the setup:

> Set up Symphony for my repository based on
> https://github.com/zack-nova/symphony/blob/main/elixir/README.md

## Relationship to upstream

This repository intentionally keeps the Symphony name for now because the runtime still implements
the same orchestration model: poll an issue tracker, create a per-issue workspace, launch Codex in
app-server mode, and keep the agent working until the issue reaches a workflow-defined handoff or
terminal state.

The features in this fork are intentionally shaped so they can be split if upstream maintainers want
them:

1. Tracker adapter abstractions and normalized issue model
2. Minimal GitHub label-state tracker support
3. State-specific prompts
4. Active state guidance refresh
5. Setup/readiness documentation and preflight contracts

Until there is clear upstream direction, this fork should be treated as an integration branch and
operational reference rather than a drop-in replacement for OpenAI's reference implementation.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
