#!/usr/bin/bash
set -euo pipefail

install -m 0755 -d /etc/apt/keyrings

# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID}"
DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" |
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) " \
     "signed-by=/etc/apt/keyrings/docker.gpg] " \
     "https://download.docker.com/linux/${DISTRO_ID} " \
     "${DISTRO_CODENAME} stable" \
     > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get -y --no-install-recommends install \
        docker-buildx-plugin docker-ce-cli docker-compose-plugin

rm -rf "$0" /var/lib/apt/lists/*
