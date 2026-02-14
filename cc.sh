#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
export CC_WORKDIR="${CC_WORKDIR:-$(pwd -P)}"

exec docker compose \
  -f "$SCRIPT_DIR/compose.yml" \
  --project-directory "$SCRIPT_DIR" \
  run --rm cli "$@"
