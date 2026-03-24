# Casual Capsule

Containerized CLI workspace for AI coding agents (`codex`, Copilot CLI) with
common developer tools.

## Project Structure

- `Dockerfile`: Main image based on `debian:trixie-slim`; installs mise
  at build time to manage Node, Python, and agent utilities (`rg`, `fd`,
  `jq`, `bat`, `eza`, `shellcheck`, `gh`, `tree`), plus Docker CLI,
  Compose plugin, and Copilot CLI.
- `docker/mise.toml`: Declares the mise-managed tool versions installed
  into the image.
- `compose.yml`: Local compose service (`cli`) that builds from `Dockerfile`
  and adds Docker socket access via `DOCKER_GID`. The container user
  matches the host user's UID/GID (auto-detected by `capsule.sh`);
  override with `CAPSULE_UID`/`CAPSULE_GID`. Also sets hostname `capsule`
  and persists mise tool data in a named volume.
- `capsule.sh`: Launcher script for running the CLI from any project
  directory.
- `tests/test_capsule.sh`: Bash test suite for launcher and Compose contract.

## Prerequisites

- Docker Engine 24+ and Docker Compose v2

## Usage

### 1. Build the main image

```bash
docker build -t casual-capsule:latest .
```

### 2. Run the main image (interactive shell)

```bash
docker run --rm -it \
  -e DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)" \
  -w /home/workspace \
  -v "$PWD:/home/workspace" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  casual-capsule:latest
```

The entrypoint runs as root, adjusts the container user to
`CAPSULE_UID`:`CAPSULE_GID` (default `1000:100`), adds it to the
`DOCKER_GID` group, sets `HOME`/`USER`/`LOGNAME`, and drops privileges.
No `--user` or `--group-add` flags required.

Inside container:

```bash
copilot
```

### 3. Use `capsule.sh` (recommended)

`capsule.sh` sets `CAPSULE_WORKDIR` to your current directory and runs the
CLI service via Compose. It auto-detects the host user's UID/GID via
`id -u`/`id -g` and `DOCKER_GID` from the active Docker socket (falling
back to `991` on macOS, `999` on Linux). If UID/GID detection fails
(e.g. `id` is unavailable), it falls back to `1000:100` and prints a
warning. The entrypoint handles UID/GID adjustment and Docker socket
group membership at startup.
On the first run in a new directory, `capsule.sh` prompts for explicit
approval and records the approved path in `~/.config/capsule`
(overridable via `CAPSULE_CONFIG`).

Override UID/GID or DOCKER_GID via environment:

```bash
CAPSULE_UID=2000 CAPSULE_GID=2000 capsule
```

Bake a custom UID/GID into the image (avoids runtime `chown`):

```bash
CAPSULE_UID=2000 CAPSULE_GID=2000 capsule --build
```

Launcher options:

- `-b`, `--build`: run `docker compose build cli` before `run`.
- `-h`, `--help`: show usage.
- `--`: stop launcher option parsing and pass remaining args to runtime.

From this repo:

```bash
./capsule.sh
```

From any directory, with an alias:

```bash
alias capsule="/absolute/path/to/casual-capsule/capsule.sh"
```

Add that alias to one of these files:

- Bash: `~/.bashrc` (or `~/.bash_profile`)
- Zsh: `~/.zshrc`

Then reload your shell and run:

```bash
capsule
```

Pass a command instead of the default shell:

```bash
capsule codex
capsule bash -lc "go version && node -v"
capsule docker ps
```

Build the image before starting:

```bash
capsule --build
capsule -b codex
```

Use `--` when arguments overlap launcher flags:

```bash
capsule -- --build true
```

### 4. Use Docker Compose directly

```bash
docker compose run --rm cli
```

Build and run in one step:

```bash
docker compose run --rm --build cli
```

If Docker socket permissions fail, set `DOCKER_GID` and retry:

```bash
# Linux
export DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"
# macOS
export DOCKER_GID="$(stat -f '%g' /var/run/docker.sock)"

docker compose run --rm cli
```

### 5. Run tests

From this repo:

```bash
./tests/test_capsule.sh
```

The tests use command stubs, so they do not require a running Docker daemon.

### 6. Included agent tooling

The image includes utilities commonly used by coding agents:

- `rg` (`ripgrep`) for fast content search
- `fd` for fast file discovery
- `jq` for JSON filtering and inspection
- `bat` for syntax-highlighted file viewing
- `eza` for enhanced directory listing
- `shellcheck` for shell script linting
- `gh` for GitHub CLI operations
- `tree` for directory structure visualization

These tools are declared in `docker/mise.toml` and installed via mise.

Verify inside capsule:

```bash
capsule bash -lc "rg --version && fd --version && jq --version && \
  shellcheck --version && gh --version && tree --version"
```

## Security Note

This setup mounts `/var/run/docker.sock` into the container, giving it
host-level Docker access. Do not use with untrusted code or shared hosts.

## License

Copyright 2026 Cursor Insight

Licensed under the [Apache License, Version 2.0](LICENSE).
