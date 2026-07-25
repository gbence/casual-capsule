#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# Copyright (C) 2026- Cursor Insight
#
# SPDX-License-Identifier: Apache-2.0
#-------------------------------------------------------------------------------
# Sync the graphify `/graphify` skill into the agent config directories under
# the home volume.
#
# The image installs the `graphify` CLI on PATH, but each agent (Claude Code,
# Codex, Antigravity) loads the skill from files under $HOME. $HOME is a
# persistent volume that a build cannot seed once it already exists, so the
# skill is installed here at container start instead. A version stamp keeps it
# to a no-op on every start except the first and after a graphify version bump.
#
# Runs as the unprivileged `user`, invoked from docker/entrypoint.sh. It must
# never abort container start: every failure path exits 0 and the caller only
# warns.
#-------------------------------------------------------------------------------

set -u

readonly VERSION_FILE="/usr/local/share/graphify-version"
readonly HOME_DIR="${HOME:-/home/user}"
readonly STAMP_DIR="$HOME_DIR/.cache/capsule"
readonly STAMP_FILE="$STAMP_DIR/graphify-skills"

# Opt out entirely.
if [[ "${CAPSULE_SKIP_SKILL_SYNC:-}" == "1" ]]; then
  exit 0
fi

# Do nothing when graphify is absent (e.g. a custom MISE_SYSTEM_TOOLS that
# drops it).
if ! command -v graphify >/dev/null 2>&1; then
  exit 0
fi

# Current graphify version: read the build-stamped version file (no Python
# spawn). Fall back to `graphify --version` if that is missing, and to a
# sentinel if even that fails, so the stamp logic stays well-defined.
current="$(cat "$VERSION_FILE" 2>/dev/null)"
if [[ -z "$current" ]]; then
  current="$(graphify --version 2>/dev/null | awk '{print $NF}')"
fi
current="${current:-unknown}"

# Skip when the stamp already records this version.
if [[ -f "$STAMP_FILE" ]] \
     && [[ "$(cat "$STAMP_FILE" 2>/dev/null)" == "$current" ]]; then
  exit 0
fi

# Install from within $HOME so nothing can land in the mounted workspace.
cd "$HOME_DIR" || exit 0

# One platform per invocation: a second differing --platform value is an error.
for platform in claude codex antigravity; do
  graphify install --platform "$platform" >/dev/null 2>&1 || true
done

# Record the synced version so later starts are a no-op.
mkdir -p "$STAMP_DIR" 2>/dev/null || true
printf '%s\n' "$current" >"$STAMP_FILE" 2>/dev/null || true

exit 0
