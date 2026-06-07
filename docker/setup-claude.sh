#!/usr/bin/bash
set -euo pipefail

CLAUDE_CODE_CHANNEL="${CLAUDE_CODE_CHANNEL:-stable}"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-}"
CLAUDE_CODE_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
    -o /etc/apt/keyrings/claude-code.asc
chmod a+r /etc/apt/keyrings/claude-code.asc

if ! gpg --show-keys --with-colons /etc/apt/keyrings/claude-code.asc \
        | grep -Fq "fpr:::::::::${CLAUDE_CODE_FINGERPRINT}:"; then
    printf '%s\n' 'Claude Code signing key fingerprint mismatch.' >&2
    exit 1
fi

printf 'deb [signed-by=/etc/apt/keyrings/claude-code.asc] %s %s main\n' \
    "https://downloads.claude.ai/claude-code/apt/${CLAUDE_CODE_CHANNEL}" \
    "${CLAUDE_CODE_CHANNEL}" \
    > /etc/apt/sources.list.d/claude-code.list

apt-get update
if [ -n "$CLAUDE_CODE_VERSION" ]; then
    apt-get -y --no-install-recommends install \
        "claude-code=${CLAUDE_CODE_VERSION}"
else
    apt-get -y --no-install-recommends install claude-code
fi

rm -rf "$0" /var/lib/apt/lists/*
