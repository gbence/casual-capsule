# Casual Capsule

Containerized CLI workspace for AI coding agents (`codex`, Copilot CLI) with
common developer tools.

## What is in this repo

- `Dockerfile`: Main image based on `jdxcode/mise` with Node, Go, npm,
  Codex, OpenAI CLI, Copilot, and Vim plugin setup.
- `compose.yml`: Local compose service (`cli`) that builds from `Dockerfile`.
- `cc.sh`: Launcher script for running the CLI from any project directory.

## Prerequisites

- Docker Engine 24+ and Docker Compose v2
- OpenAI API key (`OPENAI_API_KEY`)
- Optional GitHub token (`GITHUB_TOKEN`) for GitHub/Copilot integrations

## Usage

### 1. Build the main image

```bash
docker build -t casual-capsule:latest .
```

### 2. Run the main image (interactive shell)

```bash
docker run --rm -it \
  -e OPENAI_API_KEY \
  -e GITHUB_TOKEN \
  -w /workspace \
  -v "$PWD:/workspace" \
  -v "$HOME/.codex:/home/user/.codex" \
  -v "$HOME/.config/gh:/home/user/.config/gh" \
  -v "$HOME/.local/share/gh:/home/user/.local/share/gh" \
  casual-capsule:latest
```

Inside container:

```bash
codex
copilot
```

### 3. Use `cc.sh` (recommended)

`cc.sh` sets `CC_WORKDIR` to your current directory and runs the CLI service
from this repository's Compose file. `compose.yml` also falls back to `PWD`
if `CC_WORKDIR` is not set.

From this repo:

```bash
./cc.sh
```

From any directory, with an alias:

```bash
alias cc="/absolute/path/to/casual-capsule/cc.sh"
```

Add that alias to one of these files:

- Bash: `~/.bashrc` (or `~/.bash_profile`)
- Zsh: `~/.zshrc`

Then reload your shell and run:

```bash
cc
```

Optional: pass a command instead of the default shell.

```bash
cc codex
cc bash -lc "go version && node -v"
```

### 4. Use Docker Compose directly

If you prefer direct Compose commands:

```bash
docker compose up --build
```

## Code Review Findings

### High

1. Resolved: host-specific volume mounts were replaced with `CC_WORKDIR`
   and `${HOME}` for portability.
   - `compose.yml:10`
   - `compose.yml:11`
   - `compose.yml:12`
   - `compose.yml:13`
2. Resolved: Node setup now uses a stable major (`24`) without a
   conflicting `latest` selector.
   - `Dockerfile:25`
   - `Dockerfile:26`

### Medium

1. Resolved: restart policy is now `no` for an interactive CLI service.
   - `compose.yml:8`
2. Resolved: image provisioning no longer runs `apt-get upgrade`,
   reducing package drift risk.
   - `Dockerfile:6`

### Low

1. README previously lacked runnable setup details and operational
   notes; this file now provides baseline usage.
   - `README.md:1`

## Suggested Follow-up Fixes

1. Pin base image digests for stronger reproducibility.
2. Add shell completion for `cc.sh` command argument passthrough.
