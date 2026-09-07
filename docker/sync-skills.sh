#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# Copyright (C) 2026- Cursor Insight
#
# SPDX-License-Identifier: Apache-2.0
#-------------------------------------------------------------------------------
# Refresh Graphify's vendor skill in each bundled agent's persistent home.
# A successful version stamp avoids repeated writes between image upgrades.
# Failures remain non-fatal so optional skill setup cannot block startup.
#-------------------------------------------------------------------------------

set -u

readonly VERSION_FILE="/usr/local/share/graphify-version"
readonly HOME_DIR="${HOME:-/home/user}"
readonly STAMP_DIR="$HOME_DIR/.cache/capsule"
readonly STAMP_FILE="$STAMP_DIR/graphify-skills"

if [[ "${CAPSULE_SKIP_SKILL_SYNC:-}" == "1" ]]; then
  exit 0
fi

if ! command -v graphify >/dev/null 2>&1; then
  exit 0
fi

current="$(cat "$VERSION_FILE" 2>/dev/null)"
if [[ -z "$current" ]]; then
  current="$(graphify --version 2>/dev/null | awk '{print $NF}')"
fi
current="${current:-unknown}"

if [[ -f "$STAMP_FILE" ]] \
     && [[ "$(cat "$STAMP_FILE" 2>/dev/null)" == "$current" ]]; then
  exit 0
fi

cd "$HOME_DIR" || exit 0

sync_ok=1
for platform in claude codex antigravity; do
  graphify install --platform "$platform" >/dev/null 2>&1 || sync_ok=0
done

if [[ "$sync_ok" == "1" ]]; then
  mkdir -p "$STAMP_DIR" 2>/dev/null || sync_ok=0
fi
if [[ "$sync_ok" == "1" ]]; then
  printf '%s\n' "$current" >"$STAMP_FILE" 2>/dev/null || true
fi

exit 0
