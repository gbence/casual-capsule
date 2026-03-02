#------------------------------------------------------------------------------
# Runtime
#------------------------------------------------------------------------------
FROM jdxcode/mise:2026.3 AS runtime

WORKDIR /app

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
    > /etc/apt/sources.list.d/docker.list

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    docker-buildx-plugin docker-ce-cli docker-compose-plugin \
    ca-certificates curl git gnupg sudo vim less && \
    rm -rf /var/lib/apt/lists/*

# Add user
RUN useradd -m -u 8888 -g 100 -s /bin/bash user

# Initialize mise root for 'user'
RUN mkdir -p /mise && chown -Rh user: /mise

# Automatically activate mise
RUN echo 'eval "$(mise activate bash)"' >> /etc/profile

# Switch user
USER user

# Install nodejs
RUN mise use -g node@24
RUN mise install

# Install golang
RUN mise use -g golang@1.26

# Install Codex
RUN npm install -g @openai/codex open-codex

# Install Copilot and vim extension
RUN npm install -g @github/copilot

# Remove mise's original entrypoint
ENTRYPOINT []

# By default start a shell
CMD [ "/bin/bash" ]
