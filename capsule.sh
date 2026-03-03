#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
export CAPSULE_WORKDIR="${CAPSULE_WORKDIR:-${CC_WORKDIR:-$(pwd -P)}}"
BUILD_BEFORE_RUN=0
RUNTIME_ARGS=()

usage() {
  cat <<'EOF'
Usage: capsule.sh [options] [--] [command...]

Options:
  -b, --build  Run "docker compose build cli" before runtime.
  -h, --help   Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build)
      BUILD_BEFORE_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      RUNTIME_ARGS+=("$@")
      break
      ;;
    *)
      RUNTIME_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${DOCKER_GID:-}" ]]; then
  DOCKER_SOCK_PATH=""
  DOCKER_HOST_SOCK_PATH=""

  if [[ -n "${DOCKER_HOST:-}" ]] && [[ "${DOCKER_HOST}" == unix://* ]]; then
    DOCKER_HOST_SOCK_PATH="${DOCKER_HOST#unix://}"
    if [[ -e "${DOCKER_HOST_SOCK_PATH}" ]]; then
      DOCKER_SOCK_PATH="${DOCKER_HOST_SOCK_PATH}"
    fi
  fi

  if [[ -z "${DOCKER_SOCK_PATH}" ]] && [[ -e /var/run/docker.sock ]]; then
    DOCKER_SOCK_PATH="/var/run/docker.sock"
  elif [[ -z "${DOCKER_SOCK_PATH}" ]] && command -v docker >/dev/null 2>&1; then
    CONTEXT_HOST="$(docker context inspect \
      --format '{{(index .Endpoints "docker").Host}}' 2>/dev/null || true)"
    if [[ "${CONTEXT_HOST}" == unix://* ]]; then
      DOCKER_SOCK_PATH="${CONTEXT_HOST#unix://}"
    fi
  fi

  if [[ -n "${DOCKER_SOCK_PATH}" ]] && [[ -e "${DOCKER_SOCK_PATH}" ]]; then
    if DOCKER_GID_VALUE="$(
      stat -c '%g' "${DOCKER_SOCK_PATH}" 2>/dev/null
    )"; then
      export DOCKER_GID="${DOCKER_GID_VALUE}"
    elif DOCKER_GID_VALUE="$(
      stat -f '%g' "${DOCKER_SOCK_PATH}" 2>/dev/null
    )"; then
      export DOCKER_GID="${DOCKER_GID_VALUE}"
    else
      if DOCKER_GID_VALUE="$(
        ls -ln "${DOCKER_SOCK_PATH}" 2>/dev/null | awk '{print $4}'
      )"; then
        if [[ -n "${DOCKER_GID_VALUE}" ]]; then
          export DOCKER_GID="${DOCKER_GID_VALUE}"
        fi
      fi
    fi
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && [[ "${DOCKER_GID:-}" == "20" ]]; then
    export DOCKER_GID="991"
  fi

  if [[ -z "${DOCKER_GID:-}" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      export DOCKER_GID="991"
    else
      export DOCKER_GID="999"
    fi
  fi
fi

COMPOSE_CMD=(
  docker compose
  -f "$SCRIPT_DIR/compose.yml"
  --project-directory "$SCRIPT_DIR"
)

if [[ "$BUILD_BEFORE_RUN" -eq 1 ]]; then
  "${COMPOSE_CMD[@]}" build cli
fi

if [[ "${#RUNTIME_ARGS[@]}" -gt 0 ]]; then
  exec "${COMPOSE_CMD[@]}" run --rm cli "${RUNTIME_ARGS[@]}"
fi

exec "${COMPOSE_CMD[@]}" run --rm cli
