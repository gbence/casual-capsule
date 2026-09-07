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

# Verify that Graphify and each bundled agent's vendor skill are available.
command -v graphify >/dev/null
graphify --version >/dev/null
[[ -f "$HOME/.claude/skills/graphify/SKILL.md" ]]
[[ -f "$HOME/.codex/skills/graphify/SKILL.md" ]]
[[ -f "$HOME/.gemini/config/skills/graphify/SKILL.md" ]]
[[ -f "$HOME/.claude/skills/maintain-graphify/SKILL.md" ]]
[[ -f "$HOME/.codex/skills/maintain-graphify/SKILL.md" ]]
[[ -f "$HOME/.gemini/config/skills/maintain-graphify/SKILL.md" ]]
[[ ! -e "$HOME/.claude/skills/maintain-graphify/agents" ]]
[[ -f "$HOME/.codex/skills/maintain-graphify/agents/openai.yaml" ]]
[[ ! -e "$HOME/.gemini/config/skills/maintain-graphify/agents" ]]

printf 'capsule example ok\n'
