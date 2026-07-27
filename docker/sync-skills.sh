#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# Copyright (C) 2026- Cursor Insight
#
# SPDX-License-Identifier: Apache-2.0
#-------------------------------------------------------------------------------
# Sync Graphify's vendor skill and Capsule's lifecycle skill into the agent
# config directories under the home volume.
#
# The image installs the `graphify` CLI on PATH, but each agent (Claude Code,
# Codex, Antigravity) loads the skill from files under $HOME. $HOME is a
# persistent volume that a build cannot seed once it already exists, so the
# skills are installed here at container start instead. A content-aware stamp
# keeps it a no-op except after the Graphify or Capsule skill changes.
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
readonly CAPSULE_SKILL_DIR="/usr/local/share/capsule-skills/maintain-graphify"

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

# Include Capsule's skill contents in the stamp so an image rebuild can refresh
# it even when the pinned Graphify package version stays unchanged.
capsule_skill_hash="missing"
if [[ -d "$CAPSULE_SKILL_DIR" ]]; then
  capsule_skill_hash="$(
    find "$CAPSULE_SKILL_DIR" -type f -exec cksum {} \; 2>/dev/null \
      | sort \
      | cksum \
      | awk '{print $1}'
  )"
fi
current="${current}:${capsule_skill_hash:-missing}"

# Skip when the stamp already records this version.
if [[ -f "$STAMP_FILE" ]] \
     && [[ "$(cat "$STAMP_FILE" 2>/dev/null)" == "$current" ]]; then
  exit 0
fi

# Install from within $HOME so the vendor installer cannot write into the
# mounted workspace.
cd "$HOME_DIR" || exit 0

# One platform per invocation: a second differing --platform value is an error.
sync_ok=1
for platform in claude codex antigravity; do
  graphify install --platform "$platform" >/dev/null 2>&1 || sync_ok=0
done

# Copy the Capsule-owned lifecycle skill to the matching global skill roots.
# The copy is additive so a failed refresh never destroys a working skill.
if [[ -d "$CAPSULE_SKILL_DIR" ]]; then
  skill_roots=(
    "$HOME_DIR/.claude/skills"
    "$HOME_DIR/.codex/skills"
    "$HOME_DIR/.gemini/config/skills"
  )
  for skill_root in "${skill_roots[@]}"; do
    target="$skill_root/maintain-graphify"
    if ! mkdir -p "$target" 2>/dev/null; then
      sync_ok=0
      continue
    fi
    cp -R "$CAPSULE_SKILL_DIR/." "$target/" 2>/dev/null || sync_ok=0
    # agents/ holds vendor-specific manifests (currently only Codex's
    # openai.yaml); keep it for Codex and drop it from every other agent.
    if [[ "$skill_root" != "$HOME_DIR/.codex/skills" ]]; then
      rm -rf "$target/agents" 2>/dev/null || true
    fi
  done
fi

# Only stamp a complete sync; partial failures are retried next start.
if [[ "$sync_ok" == "1" ]]; then
  mkdir -p "$STAMP_DIR" 2>/dev/null || sync_ok=0
fi
if [[ "$sync_ok" == "1" ]]; then
  printf '%s\n' "$current" >"$STAMP_FILE" 2>/dev/null || true
fi

exit 0
