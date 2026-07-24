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

# The entrypoint syncs the /graphify skill into the home volume on start.
[[ -f "$HOME/.claude/skills/graphify/SKILL.md" ]]

printf 'capsule example ok\n'
