# AGENTS.md

## Core Workflow

1. Keep changes small, focused, and easy to review.
2. Update docs when behavior or workflow changes.
3. Do not rewrite shared history unless explicitly requested.
4. Validate changes locally when practical.

## Commit Ownership

1. The repository owner creates and GPG-signs commits.
2. Agents must not run `git commit` unless explicitly asked.
3. If asked for a message, base it on currently staged changes.
4. If staged and unstaged differ, state that the message is staged-only.

## Commit Message Rules

1. Headline format: `<type>(<scope>): <Headline>`.
2. Use a prefix and capitalize the first character of the headline.
3. Keep headline length at 72 characters maximum.
4. Write the body as bullet points.
5. Write each bullet as a full sentence explaining what changed and why.

## Commit Attribution

Include an `Assisted-by` trailer for every commit where an AI agent
contributed, following the Linux kernel gen-AI attribution convention:

```
Assisted-by: AGENT_NAME:MODEL_VERSION [TOOL1] [TOOL2]
```

- `AGENT_NAME` is the name of the AI tool or framework.
- `MODEL_VERSION` is the specific model version used.
- `[TOOL1] [TOOL2]` are optional specialised analysis tools (e.g.
  `shellcheck`, `sparse`); basic tools (`git`, editors) are omitted.

Example trailer block:

```
Assisted-by: Copilot:claude-sonnet-4.6
```

## Style Rules

1. Keep code and config lines at 80 characters maximum.

## Docker and Compose

1. Prefer reproducible images by pinning key runtime/tool versions.
2. Minimize packages and run as non-root unless root is required.
3. Keep configuration portable; avoid user-specific absolute host paths.
4. Keep secrets in runtime environment or secret managers, never hardcoded.
5. For interactive shells, do not use auto-restart policies.
6. For Docker socket access, support Linux and macOS group-ID differences.

## Go Conventions

1. Keep the `main` package small and focused.
2. Prefer standard library usage unless external dependencies are needed.
3. Run `go test ./...` when tests are present.
