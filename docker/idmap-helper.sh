#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: idmap-helper.sh supports
       idmap-helper.sh prepare <source> <inside_uid> <inside_gid> \
         <host_uid> <host_gid>
       idmap-helper.sh cleanup <target>
EOF
}

die() {
  printf 'capsule-idmap-helper: %s\n' "$1" >&2
  exit 1
}

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    die "prepare and cleanup require root privileges"
  fi
}

hash_target() {
  local payload="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$payload" | sha256sum | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$payload" | shasum -a 256 | awk '{print $1}'
    return 0
  fi

  printf '%s' "$payload" | cksum | awk '{print $1}'
}

supports() {
  command -v mount >/dev/null 2>&1 || return 1
  command -v mountpoint >/dev/null 2>&1 || return 1
  mount --help 2>&1 | grep -q -- '--map-users' || return 1
  [[ -r /proc/self/ns/user ]]
}

cleanup_target() {
  local target="$1"

  if [[ -z "$target" ]]; then
    return 0
  fi

  if mountpoint -q "$target" 2>/dev/null; then
    umount "$target"
  fi

  rmdir "$target" 2>/dev/null || true
}

prepare() {
  local source="$1"
  local inside_uid="$2"
  local inside_gid="$3"
  local host_uid="$4"
  local host_gid="$5"
  local root_dir="${CAPSULE_IDMAP_ROOT:-/run/casual-capsule/idmap}"
  local target=""
  local digest=""

  require_root
  supports || die "idmapped bind mounts are not supported on this host"
  [[ -d "$source" ]] || die "source path is not a directory: $source"

  digest="$(
    hash_target \
      "$source|$inside_uid|$inside_gid|$host_uid|$host_gid"
  )"
  target="$root_dir/$digest"

  mkdir -p "$root_dir"
  cleanup_target "$target"
  mkdir -p "$target"

  mount --bind \
    --map-users "${inside_uid}:${host_uid}:1" \
    --map-groups "${inside_gid}:${host_gid}:1" \
    "$source" "$target"

  printf '%s\n' "$target"
}

cleanup() {
  local target="$1"

  require_root
  cleanup_target "$target"
}

case "${1:-}" in
  supports)
    supports
    ;;
  prepare)
    [[ "$#" -eq 6 ]] || {
      usage >&2
      exit 1
    }
    shift
    prepare "$@"
    ;;
  cleanup)
    [[ "$#" -eq 2 ]] || {
      usage >&2
      exit 1
    }
    cleanup "$2"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
