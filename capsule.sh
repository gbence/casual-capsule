#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
export CAPSULE_WORKDIR="${CAPSULE_WORKDIR:-${CC_WORKDIR:-$(pwd -P)}}"
BUILD_BEFORE_RUN=0
RUNTIME_ARGS=()
HOST_UID=""
HOST_GID=""
IDMAP_CLEANUP_MODE=""
IDMAP_CLEANUP_TARGET=""
COLIMA_CMD=()
DEFAULT_IDMAP_HELPER="$SCRIPT_DIR/docker/idmap-helper.sh"
export CAPSULE_IDMAP="${CAPSULE_IDMAP:-auto}"
export CAPSULE_IDMAP_MODE="${CAPSULE_IDMAP_MODE:-}"
CAPSULE_IDMAP_HELPER="${CAPSULE_IDMAP_HELPER:-$DEFAULT_IDMAP_HELPER}"
export CAPSULE_IDMAP_HELPER
export CAPSULE_INSIDE_UID="${CAPSULE_INSIDE_UID:-1000}"
export CAPSULE_INSIDE_GID="${CAPSULE_INSIDE_GID:-1000}"
unset CAPSULE_MOUNT_SOURCE
export CAPSULE_COLIMA_GUEST_WORKDIR="${CAPSULE_COLIMA_GUEST_WORKDIR:-}"
export CAPSULE_COLIMA_PROFILE="${CAPSULE_COLIMA_PROFILE:-}"

LEGACY_CAPSULE_UID="${CAPSULE_UID:-}"
LEGACY_CAPSULE_GID="${CAPSULE_GID:-}"
unset CAPSULE_UID CAPSULE_GID || true
export CAPSULE_RUNTIME_UID="${CAPSULE_RUNTIME_UID:-$LEGACY_CAPSULE_UID}"
export CAPSULE_RUNTIME_GID="${CAPSULE_RUNTIME_GID:-$LEGACY_CAPSULE_GID}"

warn() {
  printf 'capsule: warning: %s\n' "$1" >&2
}

die() {
  printf 'capsule: %s\n' "$1" >&2
  exit 1
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

resolve_host_ids() {
  local uid=""
  local gid=""

  if [[ -n "$HOST_UID" ]] && [[ -n "$HOST_GID" ]]; then
    return 0
  fi

  if uid="$(id -u 2>/dev/null)" && [[ -n "$uid" ]]; then
    HOST_UID="$uid"
  else
    return 1
  fi

  if gid="$(id -g 2>/dev/null)" && [[ -n "$gid" ]]; then
    HOST_GID="$gid"
  else
    return 1
  fi
}

set_legacy_runtime_ids() {
  local warned=0

  if [[ -n "${CAPSULE_RUNTIME_UID:-}" ]]; then
    export CAPSULE_UID="$CAPSULE_RUNTIME_UID"
  elif resolve_host_ids; then
    export CAPSULE_UID="$HOST_UID"
  else
    export CAPSULE_UID="$CAPSULE_INSIDE_UID"
    warned=1
  fi

  if [[ -n "${CAPSULE_RUNTIME_GID:-}" ]]; then
    export CAPSULE_GID="$CAPSULE_RUNTIME_GID"
  elif [[ -n "$HOST_GID" ]] || resolve_host_ids; then
    export CAPSULE_GID="$HOST_GID"
  else
    export CAPSULE_GID="$CAPSULE_INSIDE_GID"
    warned=1
  fi

  export CAPSULE_IDMAP_MODE="legacy"

  if [[ "$warned" -eq 1 ]]; then
    warn "cannot detect host UID/GID; using legacy defaults"
    warn "(${CAPSULE_UID}:${CAPSULE_GID})"
  fi
}

docker_context_host() {
  local context_host=""

  if ! have_command docker; then
    return 1
  fi

  context_host="$(docker context inspect \
    --format '{{(index .Endpoints "docker").Host}}' 2>/dev/null || true)"
  if [[ -n "$context_host" ]]; then
    printf '%s\n' "$context_host"
    return 0
  fi

  return 1
}

colima_cmd_init() {
  COLIMA_CMD=(colima)
  if [[ -n "${CAPSULE_COLIMA_PROFILE:-}" ]]; then
    COLIMA_CMD+=(--profile "$CAPSULE_COLIMA_PROFILE")
  fi
}

prepare_local_idmap_mount() {
  local mapped=""

  if ! resolve_host_ids; then
    warn "cannot detect host UID/GID for Linux idmapped mounts"
    return 1
  fi

  if [[ ! -x "$CAPSULE_IDMAP_HELPER" ]]; then
    warn "idmap helper is not executable: $CAPSULE_IDMAP_HELPER"
    return 1
  fi

  if ! "$CAPSULE_IDMAP_HELPER" supports >/dev/null 2>&1; then
    warn "host mount tooling does not support idmapped binds"
    return 1
  fi

  if ! mapped="$(
    sudo "$CAPSULE_IDMAP_HELPER" prepare "$CAPSULE_WORKDIR" \
      "$CAPSULE_INSIDE_UID" "$CAPSULE_INSIDE_GID" \
      "$HOST_UID" "$HOST_GID"
  )"; then
    warn "failed to prepare Linux idmapped workspace"
    return 1
  fi

  if [[ -z "$mapped" ]]; then
    warn "idmap helper returned an empty Linux workspace mount"
    return 1
  fi

  export CAPSULE_UID="$CAPSULE_INSIDE_UID"
  export CAPSULE_GID="$CAPSULE_INSIDE_GID"
  export CAPSULE_MOUNT_SOURCE="$mapped"
  export CAPSULE_IDMAP_MODE="linux"
  IDMAP_CLEANUP_MODE="local"
  IDMAP_CLEANUP_TARGET="$mapped"
}

prepare_colima_idmap_mount() {
  local context_host=""
  local guest_workdir=""
  local mapped=""

  if ! have_command colima; then
    warn "Colima is not available for macOS idmapped mounts"
    return 1
  fi

  if ! resolve_host_ids; then
    warn "cannot detect host UID/GID for Colima idmapped mounts"
    return 1
  fi

  if [[ ! -r "$CAPSULE_IDMAP_HELPER" ]]; then
    warn "idmap helper is not readable: $CAPSULE_IDMAP_HELPER"
    return 1
  fi

  context_host="$(docker_context_host || true)"
  if [[ "$context_host" != *".colima/"* ]] && \
     [[ "$context_host" != *"colima"* ]]; then
    warn "active Docker context is not backed by Colima"
    return 1
  fi

  colima_cmd_init
  if ! "${COLIMA_CMD[@]}" status >/dev/null 2>&1; then
    warn "Colima is not running"
    return 1
  fi

  guest_workdir="${CAPSULE_COLIMA_GUEST_WORKDIR:-$CAPSULE_WORKDIR}"
  if ! "${COLIMA_CMD[@]}" ssh -- test -d "$guest_workdir" \
    >/dev/null 2>&1; then
    warn "Colima guest path is unavailable: $guest_workdir"
    return 1
  fi

  if ! mapped="$(
    "${COLIMA_CMD[@]}" ssh -- sudo bash -s -- prepare \
      "$guest_workdir" "$CAPSULE_INSIDE_UID" \
      "$CAPSULE_INSIDE_GID" "$HOST_UID" "$HOST_GID" \
      < "$CAPSULE_IDMAP_HELPER"
  )"; then
    warn "failed to prepare Colima idmapped workspace"
    return 1
  fi

  if [[ -z "$mapped" ]]; then
    warn "idmap helper returned an empty Colima workspace mount"
    return 1
  fi

  export CAPSULE_UID="$CAPSULE_INSIDE_UID"
  export CAPSULE_GID="$CAPSULE_INSIDE_GID"
  export CAPSULE_MOUNT_SOURCE="$mapped"
  export CAPSULE_IDMAP_MODE="colima"
  IDMAP_CLEANUP_MODE="colima"
  IDMAP_CLEANUP_TARGET="$mapped"
}

select_workspace_mode() {
  case "$CAPSULE_IDMAP" in
    auto|force|off)
      ;;
    *)
      die "CAPSULE_IDMAP must be one of: auto, force, off"
      ;;
  esac

  if [[ -n "${CAPSULE_RUNTIME_UID:-}" ]] || \
     [[ -n "${CAPSULE_RUNTIME_GID:-}" ]]; then
    if [[ "$CAPSULE_IDMAP" == "force" ]]; then
      die "CAPSULE_RUNTIME_UID/GID and CAPSULE_IDMAP=force conflict"
    fi
    CAPSULE_IDMAP="off"
  fi

  if [[ "$CAPSULE_IDMAP" == "off" ]]; then
    set_legacy_runtime_ids
    return 0
  fi

  case "$(uname -s)" in
    Linux)
      if prepare_local_idmap_mount; then
        return 0
      fi
      ;;
    Darwin)
      if prepare_colima_idmap_mount; then
        return 0
      fi
      ;;
  esac

  if [[ "$CAPSULE_IDMAP" == "force" ]]; then
    die "idmapped workspace is unavailable on this host"
  fi

  warn "idmapped workspace unavailable; falling back to runtime UID/GID"
  set_legacy_runtime_ids
}

cleanup_idmap_mount() {
  local status=$?

  trap - EXIT INT TERM
  if [[ -z "$IDMAP_CLEANUP_TARGET" ]]; then
    exit "$status"
  fi

  case "$IDMAP_CLEANUP_MODE" in
    local)
      sudo "$CAPSULE_IDMAP_HELPER" cleanup "$IDMAP_CLEANUP_TARGET" \
        >/dev/null 2>&1 || true
      ;;
    colima)
      colima_cmd_init
      "${COLIMA_CMD[@]}" ssh -- sudo bash -s -- cleanup \
        "$IDMAP_CLEANUP_TARGET" < "$CAPSULE_IDMAP_HELPER" \
        >/dev/null 2>&1 || true
      ;;
  esac

  exit "$status"
}

usage() {
  cat <<'EOF'
Usage: capsule.sh [options] [--] [command...]

Options:
  -b, --build  Run "docker compose build cli" before runtime.
  -h, --help   Show this help message.

Environment:
  CAPSULE_IDMAP    Workspace mode: auto, force, or off.
  CAPSULE_INSIDE_UID  Fixed in-capsule UID for idmapped mode.
  CAPSULE_INSIDE_GID  Fixed in-capsule GID for idmapped mode.
  CAPSULE_RUNTIME_UID Legacy runtime UID override.
  CAPSULE_RUNTIME_GID Legacy runtime GID override.
  CAPSULE_UID      Legacy runtime UID compatibility alias.
  CAPSULE_GID      Legacy runtime GID compatibility alias.
  DOCKER_GID       Docker socket GID (auto-detected).
  CAPSULE_WORKDIR  Workspace directory (default: cwd).
  CAPSULE_MOUNT_SOURCE  Prepared workspace source path for Compose.
  CAPSULE_COLIMA_GUEST_WORKDIR  Colima guest path for the workspace.
  CAPSULE_COLIMA_PROFILE  Optional Colima profile name.
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

trap cleanup_idmap_mount EXIT INT TERM

if [[ -z "${DOCKER_GID:-}" ]]; then
  DOCKER_SOCK_PATH=""
  DOCKER_HOST_SOCK_PATH=""
  CONTEXT_HOST="$(docker_context_host || true)"

  if [[ -n "${DOCKER_HOST:-}" ]] && [[ "${DOCKER_HOST}" == unix://* ]]; then
    DOCKER_HOST_SOCK_PATH="${DOCKER_HOST#unix://}"
    if [[ -e "${DOCKER_HOST_SOCK_PATH}" ]]; then
      DOCKER_SOCK_PATH="${DOCKER_HOST_SOCK_PATH}"
    fi
  fi

  if [[ -z "${DOCKER_SOCK_PATH}" ]] && [[ -e /var/run/docker.sock ]]; then
    DOCKER_SOCK_PATH="/var/run/docker.sock"
  elif [[ -z "${DOCKER_SOCK_PATH}" ]] && \
       [[ "${CONTEXT_HOST}" == unix://* ]]; then
    DOCKER_SOCK_PATH="${CONTEXT_HOST#unix://}"
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

select_workspace_mode

if [[ "${#RUNTIME_ARGS[@]}" -gt 0 ]]; then
  "${COMPOSE_CMD[@]}" run --rm cli "${RUNTIME_ARGS[@]}"
  exit $?
fi

"${COMPOSE_CMD[@]}" run --rm cli
