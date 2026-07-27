#!/usr/bin/env bash
#-------------------------------------------------------------------------------
# Copyright (C) 2026- Cursor Insight
#
# SPDX-License-Identifier: Apache-2.0
#-------------------------------------------------------------------------------
# Verify that the example project runs inside the expected Capsule workspace
# and setup.
#-------------------------------------------------------------------------------

set -euo pipefail

[[ "$(pwd -P)" == "/home/workspace" ]]
[[ "$(id -un)" == "user" ]]
[[ "${HOME:-}" == "/home/user" ]]
[[ "${USER:-}" == "user" ]]
[[ "${LOGNAME:-}" == "user" ]]

grep -Fxq 'capsule example fixture' fixture.txt

# graphify ships in the image and must run as the unprivileged user. The
# --version call also proves the uv-managed interpreter is readable by `user`
# (it is not if uv's Python dir was left under root's home).
command -v graphify >/dev/null
graphify --version >/dev/null

# The entrypoint syncs both Graphify skills into each agent's global skill
# directory on start.
[[ -f "$HOME/.claude/skills/graphify/SKILL.md" ]]
[[ -f "$HOME/.codex/skills/graphify/SKILL.md" ]]
[[ -f "$HOME/.gemini/config/skills/graphify/SKILL.md" ]]
[[ -f "$HOME/.claude/skills/maintain-graphify/SKILL.md" ]]
[[ -f "$HOME/.codex/skills/maintain-graphify/SKILL.md" ]]
[[ -f "$HOME/.gemini/config/skills/maintain-graphify/SKILL.md" ]]

# The OpenAI skill manifest is Codex-only; the sync drops the vendor-specific
# agents/ dir from every other agent's copy.
[[ -f "$HOME/.codex/skills/maintain-graphify/agents/openai.yaml" ]]
[[ ! -e "$HOME/.claude/skills/maintain-graphify/agents" ]]
[[ ! -e "$HOME/.gemini/config/skills/maintain-graphify/agents" ]]

printf 'capsule example ok\n'
