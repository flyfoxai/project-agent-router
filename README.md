# Project Agent Router

Project Agent Router helps an automation system work with more than one project without mixing them up.

It keeps a small project registry, reads user commands, decides which project the command belongs to, and refuses to continue when the target project is unclear or the requested action is risky.

The default mode is deliberately conservative:

- It can identify and switch between projects.
- It can remember a current project for a conversation.
- It can prepare a dry-run work order.
- It can accept a limited set of Feishu commands.
- It does not automatically create workers.
- It does not automatically push, merge, publish, or edit another project.
- It does not store secrets in the repository.

## Why This Exists

When one assistant or gateway is used for several projects, vague requests become dangerous.

For example:

- "Continue the work."
- "Check the project."
- "Push this."
- "Switch to the other repo."

Those commands are easy for a human to understand in context, but unsafe for an automated system unless the project and permissions are clear.

Project Agent Router adds a project-aware layer in front of execution. It asks: which project is this about, is the route confident, and is the action allowed?

## What It Can Do

The current version supports:

- A registry of known projects in `config/projects.yaml`.
- Explicit project selection by project ID or alias.
- Current-project and default-project conversation state.
- Project headers for reports and work orders.
- Dry-run work order generation.
- Feishu command intake for project management commands.
- Webhook checks for token, signature, duplicate events, rate limits, and user/project allowlists.
- Local validation scripts for the main routing and safety rules.

The repository currently includes two sample project entries:

- `ask`
- `project-agent-router`

You can add or replace project entries in `config/projects.yaml`.

## How Project Selection Works

The router prefers clear instructions. In simple terms, it checks:

1. Did the user name a project directly?
2. Did the user use a known project alias?
3. Is there a current project in the conversation?
4. Is there a default project?
5. Is this only a system/status question?
6. If none of those are clear, block and ask for clarification.

This means a command like this can be routed:

```text
/project use project-agent-router
```

But a command like this should be blocked:

```text
继续做
```

The point is to avoid acting on the wrong repository.

## Feishu Commands

The Feishu adapter is limited to project-management commands by default.

Supported command shapes include:

```text
/project list
/project current
/project use <project_id>
/project default <project_id>
/project clear
/system status
/orchestration status
```

The adapter checks users, projects, command text, duplicate events, and rate limits before it calls the conversation router.

Secrets should come from environment variables. Do not commit real Feishu tokens, signing keys, app secrets, or API keys.

## Safety Defaults

Project Agent Router treats routing as preparation, not execution.

By default:

- Worker auto-dispatch is disabled.
- Gateway auto-dispatch is disabled.
- Real project changes require separate human approval.
- Risky Git operations require explicit approval.
- Low-confidence routing is blocked.
- Runtime state and logs are kept out of Git.

This makes the project useful as a control layer before automation is allowed to do real work.

## Repository Layout

```text
config/
  projects.yaml
  feishu-command-adapter.yaml

scripts/
  gateway/
    project-router.rb
  conversation/
    project-conversation-router.rb
  adapters/feishu/
    feishu-command-adapter.rb
    feishu-webhook-security-gate.rb
    feishu-webhook-server.rb
  validation/
    verify-*.rb

templates/
  a2a-work-order-protocol.md
  gateway-project-routing-gate.md
  task-guard-project-registry-gate.md
  channel-agnostic-conversation-adapter.md
```

Local runtime files may appear under `logs/`, `state/`, `reports/validation-evidence/`, or task-specific folders. They are not meant to be committed by default.

## Quick Start

Enter the repository:

```bash
cd /path/to/project-agent-router
```

Check Ruby:

```bash
ruby --version
```

List the registered projects:

```bash
cat config/projects.yaml
```

Try a routing command:

```bash
ruby scripts/gateway/project-router.rb --input "use project-agent-router"
```

Run the main checks:

```bash
ruby scripts/validation/verify-task-guard-project-registry.rb
ruby scripts/validation/verify-gateway-project-routing.rb
ruby scripts/validation/verify-channel-agnostic-conversation-adapter.rb
ruby scripts/validation/verify-p5a-feishu-command-ingress.rb
ruby scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb
ruby scripts/validation/verify-p5c-feishu-limited-live-integration.rb
```

## Adding A Project

To add a project:

1. Add a new entry under `projects` in `config/projects.yaml`.
2. Give it a stable `project_id`.
3. Add aliases users are likely to type.
4. Set its workspace path and Git root.
5. Define whether dispatch is manual-only.
6. Add protected paths and forbidden Git operations.
7. Run the validation scripts.

Keep project names and aliases clear. The router is only useful when it can tell projects apart.

## Current Status

Project Agent Router is ready as a small, local-first project routing layer.

It is best used before execution, not as a full automation platform. The safe workflow is:

1. Identify the project.
2. Confirm the action.
3. Produce a dry-run result.
4. Ask for approval before any real write, push, merge, publish, or worker dispatch.

## Roadmap

Possible next steps:

- Add a `LICENSE`.
- Add CI for the Ruby validation scripts.
- Document the project registry schema.
- Add examples for more project entries.
- Add more input channels such as CLI, GitHub Issues, Slack, or a generic webhook.
- Add an approval flow before any real execution is allowed.
