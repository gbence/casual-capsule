# Casual Capsule

Containerized CLI workspace for AI coding agents (`codex`, Copilot CLI) with
common developer tools.

## Project Structure

- `Dockerfile`: Main image based on `jdxcode/mise` with Node, Go,
  Codex, Open Codex, Docker CLI, Compose plugin, Copilot CLI, and
  agent utilities (`rg`, `fd`, `jq`, `shellcheck`, `gh`, `tree`).
  The image now keeps a fixed in-capsule `user` at `1000:1000`.
- `compose.yml`: Local compose service (`cli`) that builds from
  `Dockerfile`, mounts the workspace from `CAPSULE_MOUNT_SOURCE`
  when present, and adds Docker socket access via `DOCKER_GID`.
- `capsule.sh`: Launcher script for running the CLI from any project
  directory. On Linux it prefers an idmapped workspace bind; on
  macOS it can prepare the bind inside a Colima VM.
- `docker/idmap-helper.sh`: Host-side helper that creates and
  cleans up Linux idmapped bind mounts.
- `tests/test_capsule.sh`: Bash test suite for the launcher,
  Compose contract, and helper contract.

## Prerequisites

- Docker Engine 24+ and Docker Compose v2
- Linux host or Colima guest with a recent kernel that supports
  idmapped mounts
- `mount(8)` with `--map-users` and `--map-groups`
- `sudo` access for Linux idmapped bind preparation

## Runtime Model

The capsule now prefers a fixed in-capsule identity and maps the
workspace to it instead of rewriting the container user to match the
host by default.

- Default in-capsule user: `1000:1000`
- Linux default: create an idmapped bind so a host tree owned by
  `501:20` appears as `1000:1000` inside the capsule and new files
  map back to the host identity.
- macOS with Colima: create the idmapped bind inside the Colima VM,
  then pass that guest path to Docker.
- Legacy fallback: if idmapped mounts are unavailable, `capsule.sh`
  falls back to the old runtime UID/GID matching path.

The runtime fallback is still available explicitly via
`CAPSULE_IDMAP=off`, `CAPSULE_RUNTIME_UID`, `CAPSULE_RUNTIME_GID`,
or the legacy compatibility aliases `CAPSULE_UID` and `CAPSULE_GID`.

## Usage

### 1. Build the main image

```bash
docker build -t casual-capsule:latest .
```

### 2. Run the main image directly

```bash
docker run --rm -it \
  -e DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)" \
  -e CAPSULE_UID=1000 \
  -e CAPSULE_GID=1000 \
  -w /home/workspace \
  -v "$PWD:/home/workspace" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  casual-capsule:latest
```

The entrypoint keeps the default capsule user at `1000:1000`, adds it
to the `DOCKER_GID` group, sets `HOME`/`USER`/`LOGNAME`, and drops
privileges. If you pass a different `CAPSULE_UID`/`CAPSULE_GID`, it
can still fall back to runtime user rewriting.

Inside the container:

```bash
codex
copilot
```

### 3. Use `capsule.sh` (recommended)

`capsule.sh` sets `CAPSULE_WORKDIR` to your current directory and runs
the CLI service via Compose.

On Linux:

- `CAPSULE_IDMAP=auto` (default) tries to create an idmapped bind with
  `docker/idmap-helper.sh` via `sudo`.
- `CAPSULE_IDMAP=force` requires idmapped mounts and errors if they are
  unavailable.
- `CAPSULE_IDMAP=off` disables idmapped mounts and falls back to
  runtime UID/GID matching.

On macOS with Colima:

- The active Docker context must point at Colima.
- The wrapper prepares the idmapped bind inside the Colima VM.
- `CAPSULE_COLIMA_GUEST_WORKDIR` can override the guest-side path when
  it differs from the host path.
- `CAPSULE_COLIMA_PROFILE` selects a non-default Colima profile.

Examples:

```bash
capsule
capsule codex
capsule bash -lc "go version && node -v"
capsule docker ps
```

Force legacy behavior:

```bash
CAPSULE_IDMAP=off capsule
```

Use explicit legacy runtime IDs:

```bash
CAPSULE_RUNTIME_UID=501 CAPSULE_RUNTIME_GID=20 capsule
```

The old aliases still work and also force legacy mode:

```bash
CAPSULE_UID=501 CAPSULE_GID=20 capsule
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
# macOS / Colima wrapper host
export DOCKER_GID="$(stat -f '%g' ~/.colima/default/docker.sock)"

docker compose run --rm cli
```

### 5. Run tests

From this repo:

```bash
./tests/test_capsule.sh
```

The tests use command stubs, so they do not require a running Docker
daemon.

### 6. Included agent tooling

The image includes utilities commonly used by coding agents:

- `rg` (`ripgrep`) for fast content search
- `fd` (`fdfind`) for fast file discovery
- `jq` for JSON filtering and inspection
- `shellcheck` for shell script linting
- `gh` for GitHub CLI operations
- `tree` for directory structure visualization

Verify inside the capsule:

```bash
capsule bash -lc "rg --version && fd --version && jq --version && \
  shellcheck --version && gh --version && tree --version"
```

## Environment Reference

- `CAPSULE_IDMAP`: `auto`, `force`, or `off`.
- `CAPSULE_INSIDE_UID`: fixed in-capsule UID for idmapped mode.
  Defaults to `1000`.
- `CAPSULE_INSIDE_GID`: fixed in-capsule GID for idmapped mode.
  Defaults to `1000`.
- `CAPSULE_RUNTIME_UID`: explicit legacy runtime UID override.
- `CAPSULE_RUNTIME_GID`: explicit legacy runtime GID override.
- `CAPSULE_UID` / `CAPSULE_GID`: legacy compatibility aliases for the
  runtime overrides above.
- `CAPSULE_WORKDIR`: host workspace path.
- `CAPSULE_MOUNT_SOURCE`: pre-created workspace source path passed to
  Compose. `capsule.sh` manages this automatically.
- `CAPSULE_COLIMA_GUEST_WORKDIR`: guest-side path to use when the host
  path is not visible at the same location inside Colima.
- `CAPSULE_COLIMA_PROFILE`: optional Colima profile name.
- `DOCKER_GID`: Docker socket group ID inside the capsule.

## Security Note

This setup mounts `/var/run/docker.sock` into the container, giving it
host-level Docker access. The idmapped workspace path also requires a
privileged helper on Linux or in the Colima VM. Do not use this setup
with untrusted code or shared hosts.

## License

Copyright 2026 Cursor Insight

Licensed under the [Apache License, Version 2.0](LICENSE).
