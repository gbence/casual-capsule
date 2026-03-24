#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
export CAPSULE_WORKDIR="${CAPSULE_WORKDIR:-${CC_WORKDIR:-$(pwd -P)}}"
_CAPSULE_ID_WARN=0

# Resolve container UID: env > host id > default 1000.
if [[ -n "${CAPSULE_UID:-}" ]]; then
  export CAPSULE_UID
elif CAPSULE_UID="$(id -u 2>/dev/null)" \
     && [[ -n "$CAPSULE_UID" ]]; then
  export CAPSULE_UID
else
  export CAPSULE_UID=1000
  _CAPSULE_ID_WARN=1
fi

# Resolve container GID: env > host id > default 100.
if [[ -n "${CAPSULE_GID:-}" ]]; then
  export CAPSULE_GID
elif CAPSULE_GID="$(id -g 2>/dev/null)" \
     && [[ -n "$CAPSULE_GID" ]]; then
  export CAPSULE_GID
else
  export CAPSULE_GID=100
  _CAPSULE_ID_WARN=1
fi

if [[ "$_CAPSULE_ID_WARN" -eq 1 ]]; then
  printf 'capsule: warning: %s (%s:%s)\n' \
    "cannot detect host UID/GID; using defaults" \
    "$CAPSULE_UID" "$CAPSULE_GID" >&2
fi
BUILD_BEFORE_RUN=0
RUNTIME_ARGS=()

usage() {
  cat <<'EOF'
Usage: capsule.sh [options] [--] [command...]

Options:
  -b, --build  Run "docker compose build cli" before runtime.
  -h, --help   Show this help message.

Environment:
  CAPSULE_UID      Container user UID (auto-detected).
  CAPSULE_GID      Container user GID (auto-detected).
  DOCKER_GID       Docker socket GID (auto-detected).
  CAPSULE_WORKDIR  Workspace directory (default: cwd).
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

CAPSULE_CONFIG=${CAPSULE_CONFIG:-"${HOME}/.config/capsule"}
if ! grep -qs "^${CAPSULE_WORKDIR}\$" "${CAPSULE_CONFIG}"; then
    read -rs -n 1 -p "Allow capsule to run in ${CAPSULE_WORKDIR} (y/N)? " key
    if [[ $key == 'y' || $key == 'Y' ]]; then
        echo 'y'
        echo "${CAPSULE_WORKDIR}" >>"${CAPSULE_CONFIG}"
    else
        echo 'n'
        exit 1
    fi
fi

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
      if DOCKER_GID_VALUE="$(stat -c '%g' "${DOCKER_SOCK_PATH}")"; then
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
    MISE_VERSION=""
    if hash mise 2>/dev/null && hash jq 2>/dev/null; then
        MISE_VERSION=$(mise version --json | jq -r .latest)
    fi
    "${COMPOSE_CMD[@]}" build --build-arg "MISE_VERSION=${MISE_VERSION}" cli
fi

if [[ "${#RUNTIME_ARGS[@]}" -gt 0 ]]; then
  exec "${COMPOSE_CMD[@]}" run --rm cli "${RUNTIME_ARGS[@]}"
fi

exec "${COMPOSE_CMD[@]}" run --rm cli
