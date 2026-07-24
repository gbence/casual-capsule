# syntax=docker/dockerfile:1.10
# Disabled hadolint checkers:
#  - DL3002: Last user should not be root.
#  - DL3008: Pin versions in `apt-get install`.
# hadolint global ignore=DL3002,DL3008

ARG DEBIAN_VERSION=trixie

#------------------------------------------------------------------------------
# Runtime
#------------------------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim AS runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# https://docs.docker.com/build/cache/
RUN --mount=type=cache,id=apt-global,sharing=locked,target=/var/cache/apt \
    apt-get update && \
    apt-get -y --no-install-recommends install \
    bash-completion build-essential busybox ca-certificates curl file git \
    gnupg less openssh-client procps shellcheck sudo tree unzip vim zip && \
    rm -rf /var/lib/apt/lists/* && \
    busybox --install -s

# setup docker source and install packages
COPY --chmod=700 docker/setup-docker.sh /tmp
RUN --mount=type=cache,id=apt-global,sharing=locked,target=/var/cache/apt \
    /tmp/setup-docker.sh

# Add user (reuse existing group when GID already exists)
ARG CAPSULE_UID=1000
ARG CAPSULE_GID=100
RUN if ! getent group "${CAPSULE_GID}" >/dev/null 2>&1; then \
      groupadd -g "${CAPSULE_GID}" capsule; \
    fi && \
    useradd -l -m -u "${CAPSULE_UID}" \
      -g "${CAPSULE_GID}" -s /bin/bash user

WORKDIR /home/workspace

# Install mise
ARG MISE_VERSION=""
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
RUN curl -fsSL https://mise.run | sh

# Install system AI agents and tools with mise
ARG MISE_SYSTEM_TOOLS="antigravity-cli bat codex claude eza fd \
        gh jq node ripgrep usage uv rtk pipx:graphifyy"
# graphify installs through mise's pipx backend, which needs uv's `uvx`:
#  - MISE_PIPX_UVX forces the uvx installer instead of `pipx`, which the image
#    does not ship. `mise x node uv` also guarantees uv (and uvx) are installed
#    up front, so the parallel `mise install` never reaches pipx:graphifyy
#    before uv is ready (mise installs tools concurrently).
#  - UV_PYTHON_INSTALL_DIR: uvx builds a venv whose interpreter is an absolute
#    symlink into uv's Python dir. This RUN is root, so uv would default to
#    /root/.local/share/uv (mode 700, and the image has no system python3),
#    leaving graphify unreadable for the runtime `user`. Redirect it to a
#    world-traversable system dir. Scoped to this RUN on purpose: the later
#    `uv python install` runs as `user` and must keep uv's per-user dir.
#  - UV_LINK_MODE=copy: uv defaults to reflink/clone from its cache into the
#    install dir, which fails with EAGAIN on filesystems without copy-on-write
#    (some overlay/ZFS build hosts). Plain copies keep the build portable.
RUN --mount=type=secret,id=github_api_token,env=GITHUB_API_TOKEN,required=true \
    export UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python \
      MISE_PIPX_UVX=1 UV_LINK_MODE=copy && \
    mise x node uv -- mise install --system ${MISE_SYSTEM_TOOLS} && \
    mise use --path /etc/mise/config.toml --pin ${MISE_SYSTEM_TOOLS}

# Expose system tools on PATH independently of mise's per-directory config
# resolution. A project may set `ignored_config_paths` in its mise config to
# ignore /etc/mise/config.toml (mise's hermetic-tooling feature); without these
# symlinks every capsule-provided tool -- including the agent CLIs -- would
# vanish inside such a project. `mise activate` still prepends a project's own
# mise.toml tools, so those continue to override these baseline symlinks.
RUN for dir in $(mise bin-paths); do \
      for bin in "$dir"/*; do \
        if [ -f "$bin" ] && [ -x "$bin" ]; then \
          ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"; \
        fi; \
      done; \
    done

# Activate mise in interactive shells
COPY --chmod=644 docker/mise.sh /etc/profile.d/

# Copy entrypoint (owned by root for security)
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/

# Copy the graphify skill sync helper (run as `user` by the entrypoint)
COPY --chmod=755 docker/sync-skills.sh /usr/local/bin/

# Switch user
USER user

# Install python and uv tools
ARG PYTHON_VERSION=3.14
RUN mise x -- uv python install --default ${PYTHON_VERSION} && \
    mise x -- uv tool install ruff && \
    mise x -- uv tool install ty

# Add mise shims to path
ENV PATH="/home/user/.local/share/mise/shims:/home/user/.local/bin:$PATH"

# Entrypoint runs as root, adjusts UID/GID, drops privileges
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash", "-il"]
