# 💊 Casual Capsule

[![ci](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Base image](https://img.shields.io/badge/base-debian%3Atrixie--slim-informational?logo=debian)](Dockerfile)
[![Shell](https://img.shields.io/badge/shell-bash-green?logo=gnu-bash)](capsule.sh)
[![Shellcheck](https://img.shields.io/badge/lint-shellcheck-yellow)](https://www.shellcheck.net)
[![Tooling](https://img.shields.io/badge/tools-mise-orange)](https://mise.en.dev)
[![Tooling](https://img.shields.io/badge/tools-uv-orange)](https://docs.astral.sh/uv/)

Containerized CLI workspace for AI coding agents (Claude Code, Codex CLI) with
common developer tools.

## Table of contents

- [Prerequisites](#-prerequisites)
- [Initial setup](#-initial-setup)
  - [Phase 1: Prepare credentials](#phase-1-prepare-credentials)
  - [Phase 2: Start Capsule](#phase-2-start-capsule)
  - [Phase 3: Verify the container](#phase-3-verify-the-container)
  - [Phase 4: Verify GitHub auth](#phase-4-verify-github-auth)
  - [Phase 5: Verify Claude (optional)](#phase-5-verify-claude-optional)
  - [Phase 6: Verify Codex (optional)](#phase-6-verify-codex-optional)
- [Usage](#-usage)
- [Capsule command examples](#%EF%B8%8F-capsule-command-examples)
- [Additional features](#-additional-features)
  - [Runtime backends: podman and Docker](#runtime-backends-podman-and-docker)
  - [UID and GID detection](#uid-and-gid-detection)
  - [Directory approval list](#directory-approval-list)
  - [Private home bind mount](#private-home-bind-mount)
  - [Custom Capsule images](#custom-capsule-images)
  - [Updating your GitHub token](#updating-your-github-token)
  - [Port publishing](#port-publishing)
  - [Runtime volume mounts](#runtime-volume-mounts)
  - [Bind mounts in containers started in a Capsule](#bind-mounts-in-containers-started-in-a-capsule)
  - [Remote Docker host](#remote-docker-host)
- [Configuration reference](#-configuration-reference)
  - [Command line options](#command-line-options)
  - [Environment variables](#environment-variables)
- [Run checks and tests](#-run-checks-and-tests)
- [Included agent tooling](#-included-agent-tooling)
- [Security Note](#-security-note)
- [License](#-license)

## 📋 Prerequisites

- Docker Engine 24+ and Docker Compose v2
- Optionally rootless [podman](https://podman.io) 4.9+, to run the Capsule
  with a container engine of its own instead of the host daemon
- Access to Claude or Codex.

## 🚀 Initial setup

There is no true quick start for the first run. Capsule persists GitHub auth
state in the home volume, so it is worth doing setup in this order: prepare the
token first, then start Capsule, then verify the workspace and `gh` auth before
opening Claude or Codex. These checkpoints make later troubleshooting much
easier.

| Phase | What it proves |
| --- | --- |
| Prepare credentials | The first Capsule run can persist working GitHub auth. |
| Start Capsule | The image builds and the container starts successfully. |
| Verify the container | The workspace mount and persistent home volume work. |
| Verify GitHub auth | `gh` is already logged in before agent startup. |
| Verify your agent | Claude or Codex can read the workspace. |

### Phase 1: Prepare credentials

1.  Decide if you want to use Claude, Codex, or both.

2.  Generate a GitHub access token.

    1.  Open <https://github.com/settings/personal-access-tokens>.

    2.  Make sure that you are logged in.

    3.  Click on the "Generate new token" button.

    4.  Confirm access if the UI asks you to do so.

    5.  Fill in the "New fine-grained personal access token" form:

        *   Token name: Choose any name. For example, "Capsule".

        *   Fill in the other fields as you see fit. It's ok to leave them on
            the default values.

    6.  Click on the "Generate token" button below the form.

    7.  Click on the "Generate token" button in the popup window.

    8.  Copy the token and save it somewhere safe.

    9.  You may close the GitHub website.

    The token only needs to cover `gh` and repository access. Capsule uses
    it for `gh` auth and as a build secret when `mise` downloads tools from
    GitHub. Claude and Codex authenticate separately, in Phases 5 and 6.

3.  Create a project directory that we can use as a test.

    ```
    $ mkdir /home/myuser/myproject
    $ cd /home/myuser/myproject
    $ echo "My favorite color is purple." > AGENTS.md
    $ echo "My favorite color is purple." > CLAUDE.md
    ```

4.  Create an alias:

    ```
    alias capsule="/absolute/path/to/casual-capsule/capsule.sh"
    ```

    You might want to add this to your init script (such as `~/.bashrc` or
    `~/.zshrc`).

5.  Set `GITHUB_API_TOKEN` to the value you received from GitHub (replace
    `[GITHUB_API_TOKEN]`).

    Set this before the first build/run so the persistent home volume starts
    with working GitHub auth.

    ```
    $ export GITHUB_API_TOKEN=[GITHUB_API_TOKEN]
    ```

### Phase 2: Start Capsule

1.  Build the Capsule Docker image and start it in the current directory.

    ```
    $ capsule --build
    ```

2.  When Capsule asks the following, type "y".

    ```
    Allow capsule to run in /home/myuser/myproject (y/N)?
    ```

3.  You should see that Docker builds the Capsule image, creates a container and
    starts it:

    ```
    $ capsule --build
    Allow capsule to run in /home/myuser/myproject (y/N)? y
    [...]
    [+] build 1/1
     ✔ Image hcs-capsule:local Built
     ✔ Volume casual-capsule_home Created
    Container casual-capsule-cli-run-4d7e2776d2fd Creating
    Container casual-capsule-cli-run-4d7e2776d2fd Created
    user@capsule:/home/workspace$
    ```

    **Checkpoint:** the base image built and Capsule started successfully.

### Phase 3: Verify the container

1.  Check your workspace:

    ```
    user@capsule:/home/workspace$ cat AGENTS.md
    My favorite color is purple.
    user@capsule:/home/workspace$ cat CLAUDE.md
    My favorite color is purple.
    ```

    Your `/home/myuser/myproject` directory is mounted to `/home/workspace`
    inside the container.

    **Checkpoint:** the workspace bind mount is correct before you start an
    agent.

2.  Check the user home directory:

    ```
    user@capsule:/home/workspace$ cat /home/user/.config/gh/hosts.yml
    github.com:
        users:
            myuser:
                oauth_token: [GITHUB_API_TOKEN]
        oauth_token: [GITHUB_API_TOKEN]
        user: myuser
    ```

    The Docker daemon created a `casual-capsule_home` Docker volume when it
    started the container. This volume is mounted to `/home/user`. This volume
    is persistent and shared between Capsule instances. Use `-p` or
    `--private-home` to bind-mount `~/.capsule-home` instead.

    The `/home/user/.config/gh/hosts.yml` file should contain your GitHub API
    token.

    **Checkpoint:** the persistent home volume contains the expected GitHub
    auth configuration.

### Phase 4: Verify GitHub auth

1.  Check that you are logged in to GitHub.

    ```
    user@capsule:/home/workspace$ gh auth status
    github.com
      ✓ Logged in to github.com account myuser (/home/user/.config/gh/hosts.yml)
      - Active account: true
      - Git operations protocol: https
      - Token: [GITHUB_API_TOKEN]
    ```

    **Checkpoint:** `gh` is ready before you open Claude or Codex.

    If `gh auth status` says that you are not logged in, add your GitHub token
    to `github_api_token.txt` (inside the container) and log in manually:

    ```
    $ gh auth login --with-token < github_api_token.txt
    ```

    You can do the same when your token expires in the future.

### Phase 5: Verify Claude (optional)

1.  Start Claude Code:

    ```
    $ claude
    ```

2.  Claude asks if you trust the files in `/home/workspace`.

    Choose the response that proceeds in this folder.

3.  Log in when Claude prompts you to.

    Claude prints a URL to open in your browser. Open it on the host,
    complete the login, and paste the resulting code back into the
    container.

    Credentials are written to `/home/user`, so the persistent home volume
    keeps you logged in across Capsule sessions.

4.  Test the connection and that Claude can read `CLAUDE.md`:

    ```
    > What is my favorite color?
    ● Your favorite color is purple.
    ```

### Phase 6: Verify Codex (optional)

1.  Start Codex:

    ```
    $ codex
    ```

2.  Select "Sign in with Device Code."

3.  Follow the instructions to log in.

4.  Codex asks if you trust `/home/workspace`.

    Choose the following response: "Yes, continue".

5.  Codex probably prints the following warning:

    ```
    Codex could not find bubblewrap on PATH. Install bubblewrap with your OS
    package manager. See the sandbox prerequisites:
    https://developers.openai.com/codex/concepts/sandboxing#prerequisites.
    Codex will use the vendored bubblewrap in the meantime.
    ```

    You can continue this setup, but later you might want to fix this warning.
    There are at least two ways:

    *   One way to eliminate this warning is to run `codex` with
        `--dangerously-bypass-approvals-and-sandbox`. This disables the sandbox
        which would use `bubblewrap`.

    *   Another way to eliminate the warning is to use a custom `compose.yml`
        file that adds `privileged: True` to the `cli` service, and use a
        custom `Dockerfile` that installs the `bubblewrap` package with `apt`.
        See more information about this kind of customization in the *Custom
        Capsule images* section.

6.  Test the connection and that Codex can read `AGENTS.md`:

    ```
    › What is my favorite color?
    • Your favorite color is purple.
    ```

## 💡 Usage

Once you set up Capsule, you can start it in any project directory. You can even
start Claude or Codex directly:

```
$ cd /home/myuser/myproject
$ capsule claude
$ capsule codex
```

## ⌨️ Capsule command examples

Pass a command instead of the default shell:

```bash
capsule claude
capsule bash -lc "node -v && python --version"
capsule docker ps
```

Build the image before starting:

```bash
capsule --build
capsule -b claude
```

Build only the custom image before starting:

```bash
CAPSULE_CUSTOM_COMPOSE=/home/myuser/python-capsule/compose.yml \
  capsule --build-custom
```

Use `--` when arguments overlap launcher flags:

```bash
capsule -- --build true
```

## 🧩 Additional features

### Runtime backends: podman and Docker

Capsule can start its container two ways. The Docker backend runs
`docker compose run cli`, as it always has, and shares the host's Docker
daemon. The podman backend runs the same image as a rootless
[podman](https://podman.io) container that carries **its own container
engine**, so the chain becomes:

```
host -> podman -> capsule -> the Capsule's own engine -> your project
```

That inner engine is private to the workspace the Capsule was started for. A
project brought up inside a Capsule cannot see the host's containers or
another workspace's, and `docker compose up` on a real stack behaves the way
it does on the host.

Capsule picks the backend on its own, and `--runtime` or `CAPSULE_RUNTIME`
decides it for you:

```bash
capsule --runtime podman           # run the Capsule as a rootless container
capsule --runtime docker           # keep using docker compose
CAPSULE_RUNTIME=podman capsule     # the same choice, from the environment
```

#### What the podman backend needs

*   **Rootless podman**, which is how it runs by default. Capsule refuses a
    rootful podman rather than run your Capsule as real root.

*   **A sub-id range** for your account, from the `uidmap` package. podman
    reports it as a second entry in its id map; without one it cannot even
    unpack an image that chowns a file. Capsule reads the same report and
    falls back to the Docker backend, naming the reason.

*   **A Linux VM on macOS**, which podman manages itself (`podman machine
    init && podman machine start`). The workspace must live under `$HOME`
    for the machine to see it.

Unlike the Docker backend, no AppArmor or sysctl change is needed on Ubuntu
23.10+: podman's rootless path works there as shipped.

#### The Capsule's own engine

Inside a podman Capsule, `docker` is served by an engine of the Capsule's
own, and nothing runs until the first container command:

```
user@capsule:/home/workspace$ docker ps
capsule: starting podman API socket (first use)...
CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
```

That default engine is podman answering the **Docker API**, so the `docker`
CLI and `docker compose` drive it with no daemon at rest. Projects that need
a true Docker Engine switch to one, and the choice then sticks for the life
of the Capsule:

```
user@capsule:/home/workspace$ capsule-docker use-dockerd
capsule: starting docker daemon (first use)...
capsule: engine: dockerd
user@capsule:/home/workspace$ capsule-docker status
engine: dockerd
podman api socket: stopped
dockerd: running
```

`capsule-docker use-podman` switches back and `capsule-docker stop` stops
whatever the Capsule started. The real Engine is only present when the image
was built with `CAPSULE_WITH_DOCKERD=1`, because it is the heavier of the
two; the router says so if it is missing.

#### What differs inside a podman Capsule

*   **You are still `user`, and your files are still yours.** podman's
    `keep-id` mapping puts your host account on the image's `user`, so
    everything written in `/home/workspace` belongs to you on the host and
    no UID/GID sync or privilege drop is needed.

*   **The inner engine's storage is per workspace.** Images, volumes and
    containers live in a volume keyed to the workspace path and mounted at
    `/var/lib/capsule/inner`, so two projects never share an image cache or
    see each other's containers. `CAPSULE_INNER_VOLUME` overrides the name.

*   **The host's Docker daemon is out of reach unless you ask for it.**
    `--host-docker` binds the host socket into the Capsule for the cases
    where you deliberately want it; without the flag the Capsule only has
    its own engine.

*   **Publishing a port takes two hops.** The project publishes to the
    Capsule, and `capsule --publish` publishes the Capsule to the host, so
    a service on 8080 wants `capsule --publish 8080:8080` as well as the
    usual `ports:` entry in the project's compose file.

*   **The container is `--privileged`.** A nested engine has to mount a proc
    and stack image layers. Rootless, that grants only what your own account
    already has: the Capsule still cannot exceed you on the host.

*   **`--remote` and custom compose files need a Docker daemon**, so those
    invocations use the Docker backend and say so.

### UID and GID detection

Capsule auto-detects the host user's UID/GID via `id -u`/`id -g` and
`DOCKER_GID` from the active Docker socket (falling back to `991` on macOS,
`999` on Linux). If UID/GID detection fails (e.g. `id` is unavailable), it falls
back to `1000:100` and prints a warning. The entrypoint handles UID/GID
adjustment and Docker socket group membership at startup.

This mechanism ensures that the user inside the container can access the
`/home/workspace` directory and the host's Docker daemon.

You can override UID/GID or DOCKER_GID by using environment variables:

```bash
CAPSULE_UID=2000 CAPSULE_GID=2000 capsule
```

Bake a custom UID/GID into the image (avoids runtime `chown`):

```bash
CAPSULE_UID=2000 CAPSULE_GID=2000 capsule --build
```

### Directory approval list


On the first run in a new directory, `capsule.sh` prompts for explicit approval
and records the approved path in `~/.config/capsule` (overridable via
`CAPSULE_CONFIG`).

When `--remote` is active, Capsule checks only the remote target in that same
allowlist. Remote targets approved via `--remote` are stored as
`ssh://HOST[:PORT]/path`.

### Private home bind mount

Use `-p` or `--private-home` to replace the shared Docker volume for
`/home/user` with a bind mount from `~/.capsule-home` on the Docker daemon
host.

```bash
capsule --private-home
capsule -p --build
capsule -p -r buildbox:/srv/casual-capsule
```

This keeps Capsule state per user instead of per Docker Compose project.
When `--remote` is active, Capsule resolves `~/.capsule-home` on the remote
host. When `CAPSULE_HOST_PATH_MAP` is active inside a non-Capsule container,
Capsule resolves `~/.capsule-home` through that map; if the map does not cover
`$HOME`, set `CAPSULE_HOME_HOST_DIR` explicitly.

### Custom Capsule images

If you want to extend the Docker image or Compose configuration provided by
Capsule, you can do that by creating a custom `compose.yml` file and setting its
path in `CAPSULE_CUSTOM_COMPOSE`.

The custom `compose.yml` file must override the `cli` section.

Example layout:

```text
/home/myuser/python-capsule/
|- Dockerfile
`- compose.yml
```

Example `Dockerfile`:

```dockerfile
FROM casual-capsule-cli:latest

RUN uv tool install black
```

Example `compose.yml`:

```yaml
services:
  cli:
    image: python-capsule:local
    build:
      context: ${CAPSULE_CUSTOM_DIR}
      dockerfile: ${CAPSULE_CUSTOM_DIR}/Dockerfile
    environment:
      PYTHON_CAPSULE: "1"
```

Use it like this:

```bash
export CAPSULE_CUSTOM_COMPOSE=/home/myuser/python-capsule/compose.yml
./capsule --build
```

With a custom compose file, `capsule.sh --build` first rebuilds the base image
`casual-capsule-cli:latest`, then builds the merged custom `cli` image, and
finally starts the container from that merged configuration.

If you only want to rebuild the merged custom `cli` image, use
`capsule.sh --build-custom` instead. This flag requires
`CAPSULE_CUSTOM_COMPOSE`.

### Updating your GitHub token

The entrypoint reads the `GITHUB_API_TOKEN` secret on every container
start and calls `gh auth login --with-token` automatically.  To rotate
your token:

1. Export the new token in your shell:

   ```bash
   export GITHUB_API_TOKEN=ghp_...
   ```

2. Start a new Capsule session — the entrypoint handles the rest:

   ```bash
   capsule
   ```

The updated credentials are written to the persistent home volume and
survive subsequent restarts.  No rebuild is required.

### Port publishing

Use `--publish` to expose a port from the Capsule container on the Docker
daemon host.

```bash
capsule --publish 8080:8080
capsule --publish 8080:8080 --publish 127.0.0.1:9229:9229
```

Use `CAPSULE_PUBLISH` for repeatable port mappings in environment-based
launchers. Separate mappings with semicolons.

```bash
CAPSULE_PUBLISH="8080:8080;127.0.0.1:9229:9229" capsule
```

### Runtime volume mounts

Use `--volume` or `-v` to add extra bind mounts to the Capsule container.

```bash
capsule --volume /host/cache:/cache
capsule -v /host/data:/data -v /host/cache:/cache
```

Use `CAPSULE_VOLUME` for repeatable mounts in environment-based launchers.
Separate mount specs with semicolons.

```bash
CAPSULE_VOLUME="/host/data:/data;/host/cache:/cache" capsule
```

### Bind mounts in containers started in a Capsule

When `capsule.sh` runs inside an existing container, the path it sees may not
be a path the Docker daemon can mount. Capsule translates the current container
path back to the daemon-host path before asking Docker to create the
`/home/workspace` bind mount.

Inside a Capsule, do not reset `CAPSULE_HOST_WORKDIR`. The outer Capsule sets
it to the daemon-host workspace root, and nested launches reuse it
automatically. Use `CAPSULE_HOST_PATH_MAP` only when the current non-Capsule
container sees the same files under a different absolute path.

```bash
CAPSULE_HOST_PATH_MAP=/workspace=/home/myuser/myproject capsule
CAPSULE_HOST_PATH_MAP=/workspace=/src/project:/tmp/cache=/var/cache capsule
```

`CAPSULE_HOST_PATH_MAP` is a colon-separated list of
`container_prefix=host_prefix` pairs. The first matching prefix wins.

### Remote Docker host

Use `--remote HOST[:PORT]:/abs/path` to build and run on a remote Docker daemon
over SSH. Capsule sets `DOCKER_HOST=ssh://HOST[:PORT]` for Compose and mounts
`/abs/path` as `/home/workspace` on the remote daemon host.

```bash
capsule --remote buildbox:/srv/casual-capsule
capsule --remote buildbox:2222:/srv/casual-capsule
capsule --remote buildbox:/srv/casual-capsule --build
```

The remote target must be approved first. Use an SSH config host alias when you
need extra SSH options beyond the optional port in `HOST[:PORT]`.

## 🔧 Configuration reference

### Command line options

Usage:

```
capsule.sh [OPTIONS]
capsule.sh [OPTIONS] -- [ARGS]
```

Options:

*   `-b`, `--build`: Run `docker compose build cli` before `run`.

*   `-p`, `--private-home`: Bind-mount `~/.capsule-home` from the Docker daemon
    host to `/home/user` in the container.

*   `--build-custom`: Run `docker compose build cli` only for the merged custom
    compose configuration before `run`. Requires `CAPSULE_CUSTOM_COMPOSE`.

*   `-r HOST[:PORT]:/abs/path`, `--remote HOST[:PORT]:/abs/path`: Run
    `docker compose` against `ssh://HOST[:PORT]` and
    mount `/abs/path` as `/home/workspace` on that remote host.

*   `--runtime podman|docker|auto`: Choose the backend that runs the Capsule.
    `auto`, the default, prefers podman and falls back to Docker with the
    reason named.

*   `--host-docker`: Bind the host's Docker socket into the Capsule. Only
    meaningful on the podman backend, which is otherwise isolated from it.

*   `--publish HOST[:CONTAINER]`: Publish a container port on the host when
    running the container. May be passed multiple times.

*   `-v HOST:CONTAINER`, `--volume HOST:CONTAINER`: Bind-mount a host path into
    the runtime container. May be passed multiple times.

*   `--no-cache`: Pass `--no-cache` to the build commands triggered by
    `--build` or `--build-custom`.

*   `-h`, `--help`: Show usage message.

*   `--`: Stop launcher option parsing; pass remaining arguments to
    `docker compose run cli`.

### Environment variables

*   `CAPSULE_RUNTIME`: Backend that runs the Capsule: `auto`, `podman`, or
    `docker`.

    Default: `auto`, which prefers podman when the host can run it rootless.

*   `CAPSULE_IMAGE`: Image tag the podman backend builds and runs.

    Default: `casual-capsule:local`. Set it to run a prebuilt image, which
    also turns off the "image is not built" check.

    A prebuilt image must have been built with the same
    `CAPSULE_UID`/`CAPSULE_GID` as the host account, because keep-id
    maps you onto that uid and nothing inside can adjust it.

*   `CAPSULE_HOME_VOLUME`: podman volume mounted at `/home/user`.

    Default: `casual-capsule-home`. Ignored under `--private-home`.

*   `CAPSULE_INNER_VOLUME`: Volume holding the inner engine's images,
    volumes and containers.

    Default: derived from the workspace path, so each project gets its own.

*   `CAPSULE_WITH_DOCKERD`: Build the image with a real Docker Engine.

    Default: empty. Set to `1` at build time to make `capsule-docker
    use-dockerd` available inside the Capsule.

*   `CAPSULE_DEBUG`: Enable shell xtrace for `capsule.sh`.

    Default: empty. When set to `1`, `capsule.sh` runs with `set -x`.

*   `CAPSULE_UID`: Container user UID (user ID).

    Default: The output of `id -u` on the host. If that doesn't work, then 1000.

*   `CAPSULE_GID`: Container user GID (group ID).

    Default: The output of `id -g` on the host. If that doesn't work, then 100.

*   `DOCKER_GID`: Docker socket GID.

    Default: Auto-detected from the host.

*   `DOCKER_HOST`: Docker daemon endpoint for `docker compose`.

    Default: Docker CLI default. `--remote` sets `ssh://HOST[:PORT]`.

*   `CAPSULE_HOME_HOST_DIR`: Host path bound to `/home/user` when
    `--private-home` is active.

    Default: empty. `--private-home` resolves it to `~/.capsule-home` on the
    Docker daemon host, using `CAPSULE_HOST_PATH_MAP` when needed.

*   `CAPSULE_HOST_PATH_MAP`: Colon-separated
    `container_prefix=host_prefix` mappings for resolving daemon-host paths
    from inside non-Capsule containers.

    Default: empty. The first matching prefix wins, and the mapped host path is
    used for allowlist checks.

*   `CAPSULE_PUBLISH`: Semicolon-separated list of `--publish` specs.

    Default: empty. Each non-empty entry is passed before command-line
    `--publish` options.

*   `CAPSULE_VOLUME`: Semicolon-separated list of `--volume` specs.

    Default: empty. Each non-empty entry is passed before command-line
    `--volume` options.

*   `CAPSULE_WORKDIR`: Workspace directory.

    Default: current working directory.

*   `CAPSULE_CUSTOM_COMPOSE`: Optional custom compose override file.

    Default: empty.

*   `CAPSULE_CONFIG`: Path to the file that contains the approved directories.

    Default: `~/.config/capsule`.

*   `CAPSULE_HOST_WORKDIR`: daemon-host-visible path for `/home/workspace`.

    Default: derived from `CAPSULE_WORKDIR`. `--remote` overrides it with the
    remote workspace path.

*   `GITHUB_API_TOKEN`: Passed as a build secret for `gh` auth and for `mise`
    tool downloads from GitHub.

## 🧪 Run checks and tests

Run lint checks on the host:

```bash
$ tests/check_all.sh
```

Run the test suites on the host:

```bash
$ tests/test_all.sh
```

The podman backend is covered by the fast suite -- a mocked `podman` for the
launcher, mocked engines for the in-Capsule router -- and by an end-to-end
case that skips unless the host can run rootless containers. To exercise the
whole chain on a real host, a Capsule with its own engine and a service
running inside it, use the untracked operator check:

```bash
$ tmp/verify-podman-backend.sh
```

Run checks and tests inside a Capsule:

```bash
$ capsule tests/check_all.sh
$ capsule tests/test_all.sh
```

`check_all.sh` runs `dclint`, `hadolint`, and `shellcheck` on discovered files.
When one of these tools is missing, it prints a warning and skips that linter.

`test_all.sh` prints each suite name before running it.

*   The fast suite uses command stubs, so it does not require a running Docker
    daemon.

*   The end-to-end suite builds and runs the real capsule image when Docker and
    Compose are available. It skips cleanly when the daemon is unavailable.

    The end-to-end suite also prints the path to a per-run logfile under
    `_build/tests/`. The logfile is kept after the run and records suite events
    and plain Docker/Capsule output with UTC timestamps on every line.

## 🤖 Included agent tooling

The image includes utilities commonly used by coding agents, installed via
`mise` (configured by the `MISE_SYSTEM_TOOLS` Dockerfile ARG). Set
`MISE_SYSTEM_TOOLS` in the build environment to override the default tool list
when building through Compose:

```bash
MISE_SYSTEM_TOOLS="bat fd jq ripgrep uv" docker compose build cli
```

- `claude`: Claude Code agent CLI.
- `codex`: Codex agent CLI.
- `bat`: Syntax-highlighted file viewing.
- `eza`: Enhanced directory listing.
- `fd`: Fast file discovery.
- `gh`: GitHub CLI operations.
- `jq`: JSON filtering and inspection.
- `rg` (`ripgrep`): Fast content search.
- `uv`: Python version, tool, and environment management.

Container engines (see
[Runtime backends](#runtime-backends-podman-and-docker)):

- `podman`: The Capsule's own rootless engine, which also answers the Docker
  API so `docker` and `docker compose` work against it.
- `dockerd`: A real Docker Engine, present only when the image is built with
  `CAPSULE_WITH_DOCKERD=1`.
- `capsule-docker`: Selects which of the two `docker` talks to.

Installed via `apt`:

- `shellcheck`: Shell script linting.
- `tree`: Directory structure visualization.

Python tooling (installed via `uv`; binaries available on `PATH` via
`~/.local/bin`):

- `python`: Python runtime (version set by `PYTHON_VERSION` ARG, default
  `3.14`).
- `ruff`: Fast Python linter and formatter.
- `ty`: Python type checker.

Verify inside capsule:

```bash
capsule bash -lc "rg --version && fd --version && jq --version && \
  bat --version && eza --version && shellcheck --version && \
  gh --version && tree --version && python --version"
```

## 🔐 Security Note

This setup mounts `/var/run/docker.sock` into the container, giving it
host-level Docker access. Do not use with untrusted code or shared hosts.

## 📄 License

Copyright 2026 Cursor Insight

Licensed under the [Apache License, Version 2.0](LICENSE).
