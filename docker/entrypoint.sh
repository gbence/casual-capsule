#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------
# Runtime entrypoint.
#
# When running as root (the default), this script:
#   1. Keeps the default capsule user at 1000:1000 for idmapped
#      workspace mounts.
#   2. Optionally falls back to CAPSULE_UID/CAPSULE_GID matching
#      when the launcher disables idmapped mounts.
#   3. Adds "user" to the DOCKER_GID group for socket access.
#   4. Fixes ownership of /mise and /home/user when the runtime
#      fallback changes the UID/GID or a named volume is stale.
#   5. Sets HOME, USER, and LOGNAME (setpriv does not update
#      environment variables, so they would otherwise stay as
#      root's values from the Dockerfile USER directive).
#   6. Drops privileges via setpriv and execs the command.
#
# When running as non-root (e.g. --user flag), skips all
# adjustments and execs the command directly.
# ----------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
  exec "$@"
fi

CUR_UID="$(id -u user)"
CUR_GID="$(id -g user)"
TARGET_UID="${CAPSULE_UID:-$CUR_UID}"
TARGET_GID="${CAPSULE_GID:-$CUR_GID}"
CHANGED=0

# Adjust primary group GID when it differs.
if [ "$CUR_GID" != "$TARGET_GID" ]; then
  if ! getent group "$TARGET_GID" >/dev/null 2>&1; then
    groupadd -g "$TARGET_GID" capsule
  fi
  usermod -g "$TARGET_GID" user
  CHANGED=1
fi

# Adjust user UID when it differs.
if [ "$CUR_UID" != "$TARGET_UID" ]; then
  usermod -u "$TARGET_UID" user
  CHANGED=1
fi

# Add user to the Docker socket group when requested.
if [ -n "${DOCKER_GID:-}" ]; then
  DK_GROUP="$(getent group "$DOCKER_GID" \
    | cut -d: -f1 || true)"
  if [ -z "$DK_GROUP" ]; then
    groupadd -g "$DOCKER_GID" docker_host
    DK_GROUP="docker_host"
  fi
  usermod -aG "$DK_GROUP" user
fi

# Fix ownership when UID/GID changed or a named volume has
# stale ownership from a previous image build.
TARGET_HOME="$(getent passwd user | cut -d: -f6)"
TARGET_HOME="${TARGET_HOME:-/home/user}"
OWNER_UID="$(stat -c '%u' "$TARGET_HOME" 2>/dev/null || true)"
if [ "$CHANGED" = "1" ] || \
   [ "${OWNER_UID:-}" != "$(id -u user)" ]; then
  printf 'capsule: adjusting file ownership...\n' >&2
  chown -Rh user: /mise 2>/dev/null || true
  chown -Rh user: "$TARGET_HOME" 2>/dev/null || true
fi

# Set user environment before dropping privileges.
# setpriv does not update env vars, so HOME, USER, and
# LOGNAME would otherwise stay as root's values.
USER_HOME="$(getent passwd user | cut -d: -f6)"
export HOME="${USER_HOME:-/home/user}"
export USER=user
export LOGNAME=user

exec setpriv \
  --reuid="$(id -u user)" \
  --regid="$(id -g user)" \
  --init-groups \
  -- "$@"
