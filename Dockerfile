# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv

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
    bash-completion build-essential busybox ca-certificates curl git gnupg \
    openssh-client procps shellcheck sudo tree unzip vim zip && \
    rm -rf /var/lib/apt/lists/* && \
    busybox --install -s

WORKDIR /home/workspace

# setup docker
RUN install -m 0755 -d /etc/apt/keyrings && \
    . /etc/os-release && \
    DISTRO_ID="${ID}" && \
    DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}" && \
    curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) " \
    "signed-by=/etc/apt/keyrings/docker.gpg] " \
    "https://download.docker.com/linux/${DISTRO_ID} " \
    "${DISTRO_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list && \
    curl -fsSL \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/github-cli.gpg && \
    chmod a+r /etc/apt/keyrings/github-cli.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) " \
    "signed-by=/etc/apt/keyrings/github-cli.gpg] " \
    "https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list

RUN --mount=type=cache,id=apt-global,sharing=locked,target=/var/cache/apt \
    apt-get update && \
    apt-get -y --no-install-recommends install \
    docker-buildx-plugin docker-ce-cli docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Add user
RUN groupadd -g 1000 user && useradd -m -u 1000 -g 1000 -s /bin/bash user

# Install mise
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
RUN curl https://mise.run | sh

# Install system tools with mise
ARG MISE_SYSTEM_TOOLS="aqua:github/copilot-cli bat eza fd gh jq ripgrep usage uv"
RUN --mount=type=secret,id=github_api_token,env=GITHUB_API_TOKEN \
    mise install --system ${MISE_SYSTEM_TOOLS}

# Automatically activate mise
RUN echo 'eval "$(mise activate bash)"' >> /etc/profile
RUN echo 'eval "$(mise complete bash)"' >> /etc/profile

# Switch user
USER user

# Activate system tools ,env=GITHUB_API_TOKEN \
RUN --mount=type=secret,id=github_api_token,env=GITHUB_API_TOKEN \
    mise use -g ${MISE_SYSTEM_TOOLS} python@3.14

# GitHub token login
RUN --mount=type=secret,id=github_api_token,uid=1000 \
    [ -f /run/secrets/github_api_token ] && \
      ${MISE_INSTALL_PATH} x -- gh auth login --with-token </run/secrets/github_api_token

# Use a common AGENTS.md in the direct parent of `workspace`
COPY --chmod=644 docker/AGENTS.md /home/

# By default start a shell
CMD [ "/bin/bash", "-il" ]
