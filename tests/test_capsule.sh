#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
SCRIPT_PATH="$ROOT_DIR/capsule.sh"
COMPOSE_PATH="$ROOT_DIR/compose.yml"
DOCKERFILE_PATH="$ROOT_DIR/Dockerfile"
ENTRYPOINT_PATH="$ROOT_DIR/docker/entrypoint.sh"
IDMAP_HELPER_PATH="$ROOT_DIR/docker/idmap-helper.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

unset CAPSULE_UID CAPSULE_GID CAPSULE_RUNTIME_UID CAPSULE_RUNTIME_GID \
  CAPSULE_MOUNT_SOURCE CAPSULE_IDMAP_MODE CAPSULE_IDMAP \
  CAPSULE_IDMAP_HELPER CAPSULE_INSIDE_UID CAPSULE_INSIDE_GID \
  CAPSULE_COLIMA_GUEST_WORKDIR CAPSULE_COLIMA_PROFILE \
  DOCKER_GID DOCKER_HOST 2>/dev/null || true


PASS_COUNT=0
FAIL_COUNT=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
  printf 'PASS: %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq -- "$needle" "$file"; then
    pass "$msg"
  else
    fail "$msg (missing: $needle)"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq -- "$needle" "$file"; then
    fail "$msg (unexpected: $needle)"
  else
    pass "$msg"
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$msg"
  else
    fail "$msg (expected=$expected actual=$actual)"
  fi
}

make_mock_bin() {
  local dir="$1"
  mkdir -p "$dir"

  cat >"$dir/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "context" ]] && [[ "${2:-}" == "inspect" ]]; then
  if [[ -n "${MOCK_CONTEXT_HOST:-}" ]]; then
    printf '%s\n' "$MOCK_CONTEXT_HOST"
  fi
  exit 0
fi

if [[ "${1:-}" == "compose" ]]; then
  {
    printf 'ENV_DOCKER_GID=%s\n' "${DOCKER_GID:-}"
    printf 'ENV_CAPSULE_WORKDIR=%s\n' "${CAPSULE_WORKDIR:-}"
    printf 'ENV_CAPSULE_UID=%s\n' "${CAPSULE_UID:-}"
    printf 'ENV_CAPSULE_GID=%s\n' "${CAPSULE_GID:-}"
    printf 'ENV_CAPSULE_MOUNT_SOURCE=%s\n' "${CAPSULE_MOUNT_SOURCE:-}"
    printf 'ENV_CAPSULE_IDMAP_MODE=%s\n' "${CAPSULE_IDMAP_MODE:-}"
    printf 'ARGS=%s\n' "$*"
  } >>"${MOCK_LOG:?MOCK_LOG is required}"
  exit 0
fi

printf 'unexpected docker call: %s\n' "$*" >&2
exit 1
EOF

  cat >"$dir/stat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${MOCK_STAT_FAIL:-}" ]]; then
  exit 1
fi
printf '%s\n' "${MOCK_STAT_GID:-999}"
EOF

  cat >"$dir/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${MOCK_UNAME:-Linux}"
EOF

  cat >"$dir/ls" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${MOCK_LS_FAIL:-}" ]] || [[ -n "${MOCK_STAT_FAIL:-}" ]]; then
  exit 1
fi
/bin/ls "$@"
EOF

  cat >"$dir/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${MOCK_ID_FAIL:-}" ]]; then
  exit 1
fi
case "${1:-}" in
  -u) printf '%s\n' "${MOCK_ID_UID:-1000}" ;;
  -g) printf '%s\n' "${MOCK_ID_GID:-1000}" ;;
  *) /usr/bin/id "$@" ;;
esac
EOF

  cat >"$dir/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${MOCK_SUDO_FAIL:-}" ]]; then
  exit 1
fi
exec "$@"
EOF

  cat >"$dir/colima" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--profile" ]]; then
  shift 2
fi
case "${1:-}" in
  status)
    if [[ -n "${MOCK_COLIMA_FAIL:-}" ]]; then
      exit 1
    fi
    printf 'running\n'
    ;;
  ssh)
    shift
    if [[ "${1:-}" == "--" ]]; then
      shift
    fi
    if [[ "${1:-}" == "test" ]] && [[ "${2:-}" == "-d" ]]; then
      if [[ "${3:-}" == "${MOCK_COLIMA_GUEST_PATH:-}" ]]; then
        exit 0
      fi
      exit 1
    fi
    if [[ "${1:-}" == "sudo" ]] && [[ "${2:-}" == "bash" ]] && \
       [[ "${3:-}" == "-s" ]] && [[ "${4:-}" == "--" ]]; then
      case "${5:-}" in
        prepare)
          printf '%s\n' "${MOCK_COLIMA_MOUNT_SOURCE:-/run/capsule-idmap/colima}"
          ;;
        cleanup)
          exit 0
          ;;
      esac
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF

  chmod +x "$dir/docker" "$dir/stat" "$dir/uname" "$dir/ls" \
    "$dir/id" "$dir/sudo" "$dir/colima"
}

make_mock_helper() {
  local path="$1"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  supports)
    if [[ -n "${MOCK_HELPER_UNSUPPORTED:-}" ]]; then
      exit 1
    fi
    ;;
  prepare)
    if [[ -n "${MOCK_HELPER_FAIL:-}" ]]; then
      exit 1
    fi
    printf '%s\n' "${MOCK_HELPER_MOUNT_SOURCE:-/run/capsule-idmap/linux}"
    ;;
  cleanup)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$path"
}

run_capsule() {
  local mock_bin="$1"
  local log_file="$2"
  shift 2
  PATH="$mock_bin:$PATH" MOCK_LOG="$log_file" "$SCRIPT_PATH" "$@"
}

value_from_log() {
  local key="$1"
  local log_file="$2"
  grep -F "$key=" "$log_file" | tail -n1 | cut -d= -f2-
}

nth_value_from_log() {
  local key="$1"
  local index="$2"
  local log_file="$3"
  grep -F "$key=" "$log_file" | sed -n "${index}p" | cut -d= -f2-
}

test_compose_contract() {
  assert_file_contains "$COMPOSE_PATH" \
    'source: ${CAPSULE_MOUNT_SOURCE:-${CAPSULE_WORKDIR:-${PWD}}}' \
    "compose prefers CAPSULE_MOUNT_SOURCE for workspace binds"
  assert_file_contains "$COMPOSE_PATH" \
    'CAPSULE_UID=${CAPSULE_UID:-}' \
    "compose passes CAPSULE_UID to the container"
  assert_file_contains "$COMPOSE_PATH" \
    'CAPSULE_GID=${CAPSULE_GID:-}' \
    "compose passes CAPSULE_GID to the container"
  assert_file_not_contains "$COMPOSE_PATH" \
    'CAPSULE_UID: "${CAPSULE_UID:-1000}"' \
    "compose no longer bakes host UID build args"
}

test_dockerfile_tooling_contract() {
  assert_file_contains "$DOCKERFILE_PATH" 'fd-find' \
    "image installs fd-find"
  assert_file_contains "$DOCKERFILE_PATH" 'ripgrep' \
    "image installs ripgrep for rg"
  assert_file_contains "$DOCKERFILE_PATH" 'jq' \
    "image installs jq for JSON inspection"
  assert_file_contains "$DOCKERFILE_PATH" 'shellcheck' \
    "image installs shellcheck for shell linting"
  assert_file_contains "$DOCKERFILE_PATH" \
    'ln -sf /usr/bin/fdfind /usr/local/bin/fd' \
    "image exposes fd command name via fdfind symlink"
  assert_file_contains "$DOCKERFILE_PATH" 'gh' \
    "image installs gh for GitHub CLI"
  assert_file_contains "$DOCKERFILE_PATH" 'tree' \
    "image installs tree for directory visualization"
}

test_dockerfile_uid_gid_contract() {
  assert_file_not_contains "$DOCKERFILE_PATH" \
    'ARG CAPSULE_UID=1000' \
    "Dockerfile no longer exposes CAPSULE_UID as a build arg"
  assert_file_not_contains "$DOCKERFILE_PATH" \
    'ARG CAPSULE_GID=100' \
    "Dockerfile no longer exposes CAPSULE_GID as a build arg"
  assert_file_contains "$DOCKERFILE_PATH" \
    'useradd -m -u 1000 -g 1000 -s /bin/bash user' \
    "Dockerfile uses a fixed in-capsule user"
  assert_file_contains "$DOCKERFILE_PATH" \
    'COPY docker/entrypoint.sh /usr/local/bin/' \
    "Dockerfile copies entrypoint script"
  assert_file_contains "$DOCKERFILE_PATH" \
    'ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]' \
    "Dockerfile sets the runtime entrypoint"
}

test_entrypoint_contract() {
  if ! bash -n "$ENTRYPOINT_PATH"; then
    fail "entrypoint.sh has valid shell syntax"
  else
    pass "entrypoint.sh has valid shell syntax"
  fi
  assert_file_contains "$ENTRYPOINT_PATH" 'CAPSULE_UID' \
    "entrypoint still supports runtime UID fallback"
  assert_file_contains "$ENTRYPOINT_PATH" 'DOCKER_GID' \
    "entrypoint handles DOCKER_GID group"
  assert_file_contains "$ENTRYPOINT_PATH" 'setpriv' \
    "entrypoint drops privileges via setpriv"
  assert_file_contains "$ENTRYPOINT_PATH" 'stat -c' \
    "entrypoint checks named volume ownership"
}

test_helper_contract() {
  if ! bash -n "$IDMAP_HELPER_PATH"; then
    fail "idmap-helper.sh has valid shell syntax"
  else
    pass "idmap-helper.sh has valid shell syntax"
  fi
  assert_file_contains "$IDMAP_HELPER_PATH" '--map-users' \
    "idmap helper configures user mappings"
  assert_file_contains "$IDMAP_HELPER_PATH" '--map-groups' \
    "idmap helper configures group mappings"
  assert_file_contains "$IDMAP_HELPER_PATH" 'mount --bind' \
    "idmap helper creates a bind mount"
}

test_build_flag_runs_build_then_runtime() {
  local tdir="$TEST_TMPDIR/build-flag"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" --build true

  assert_equals \
    "compose -f $COMPOSE_PATH --project-directory $ROOT_DIR build cli" \
    "$(nth_value_from_log ARGS 1 "$log_file")" \
    "build flag runs compose build first"
  assert_equals \
    "compose -f $COMPOSE_PATH --project-directory $ROOT_DIR run --rm cli true" \
    "$(nth_value_from_log ARGS 2 "$log_file")" \
    "build flag still runs compose runtime"
}

test_double_dash_keeps_runtime_flags() {
  local tdir="$TEST_TMPDIR/double-dash"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" -- --build true

  local expected_args="compose -f $COMPOSE_PATH"
  expected_args="$expected_args --project-directory $ROOT_DIR"
  expected_args="$expected_args run --rm cli --build true"

  assert_equals \
    "$expected_args" \
    "$(value_from_log ARGS "$log_file")" \
    "double dash passes build-like flags to runtime command"
}

test_build_flag_without_runtime_args() {
  local tdir="$TEST_TMPDIR/build-no-args"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" -b

  assert_equals \
    "compose -f $COMPOSE_PATH --project-directory $ROOT_DIR build cli" \
    "$(nth_value_from_log ARGS 1 "$log_file")" \
    "build flag works without runtime args (build call)"
  assert_equals \
    "compose -f $COMPOSE_PATH --project-directory $ROOT_DIR run --rm cli" \
    "$(nth_value_from_log ARGS 2 "$log_file")" \
    "build flag works without runtime args (run call)"
}

test_plain_runtime_without_args() {
  local tdir="$TEST_TMPDIR/run-no-args"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file"

  assert_equals \
    "compose -f $COMPOSE_PATH --project-directory $ROOT_DIR run --rm cli" \
    "$(value_from_log ARGS "$log_file")" \
    "plain runtime works without runtime args"
}

test_linux_idmap_mode_uses_mapped_workspace() {
  local tdir="$TEST_TMPDIR/linux-idmap"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 MOCK_ID_UID=501 MOCK_ID_GID=20 \
    MOCK_HELPER_MOUNT_SOURCE=/run/capsule-idmap/linux \
    CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "1000" "$(value_from_log ENV_CAPSULE_UID "$log_file")" \
    "Linux idmap mode keeps the in-capsule UID fixed"
  assert_equals "1000" "$(value_from_log ENV_CAPSULE_GID "$log_file")" \
    "Linux idmap mode keeps the in-capsule GID fixed"
  assert_equals \
    "/run/capsule-idmap/linux" \
    "$(value_from_log ENV_CAPSULE_MOUNT_SOURCE "$log_file")" \
    "Linux idmap mode injects the mapped workspace source"
  assert_equals "linux" \
    "$(value_from_log ENV_CAPSULE_IDMAP_MODE "$log_file")" \
    "Linux idmap mode is surfaced to Compose"
}

test_auto_falls_back_to_legacy_when_helper_fails() {
  local tdir="$TEST_TMPDIR/auto-fallback"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  local err_file="$tdir/err"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 MOCK_ID_UID=501 MOCK_ID_GID=20 MOCK_HELPER_FAIL=1 \
    CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true 2>"$err_file"

  assert_equals "501" "$(value_from_log ENV_CAPSULE_UID "$log_file")" \
    "auto mode falls back to host UID on failure"
  assert_equals "20" "$(value_from_log ENV_CAPSULE_GID "$log_file")" \
    "auto mode falls back to host GID on failure"
  assert_equals "legacy" \
    "$(value_from_log ENV_CAPSULE_IDMAP_MODE "$log_file")" \
    "fallback reports legacy mode"
  assert_file_contains "$err_file" \
    'idmapped workspace unavailable; falling back to runtime UID/GID' \
    "fallback emits a warning"
}

test_force_requires_idmap_support() {
  local tdir="$TEST_TMPDIR/force-idmap"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  local err_file="$tdir/err"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  if DOCKER_GID=1111 CAPSULE_IDMAP=force MOCK_HELPER_FAIL=1 \
    CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true 2>"$err_file"; then
    fail "force mode errors when idmap setup fails"
  else
    pass "force mode errors when idmap setup fails"
  fi

  assert_file_contains "$err_file" \
    'idmapped workspace is unavailable on this host' \
    "force mode reports an idmap error"
}

test_legacy_compat_aliases_disable_idmap() {
  local tdir="$TEST_TMPDIR/legacy-alias"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 CAPSULE_UID=2000 CAPSULE_GID=2000 \
    CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "2000" "$(value_from_log ENV_CAPSULE_UID "$log_file")" \
    "legacy CAPSULE_UID alias still works"
  assert_equals "2000" "$(value_from_log ENV_CAPSULE_GID "$log_file")" \
    "legacy CAPSULE_GID alias still works"
  assert_equals "legacy" \
    "$(value_from_log ENV_CAPSULE_IDMAP_MODE "$log_file")" \
    "legacy aliases disable idmap mode"
}

test_legacy_defaults_when_id_detection_fails() {
  local tdir="$TEST_TMPDIR/id-defaults"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  local err_file="$tdir/err"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID=1111 CAPSULE_IDMAP=off MOCK_ID_FAIL=1 \
    CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true 2>"$err_file"

  assert_equals "1000" "$(value_from_log ENV_CAPSULE_UID "$log_file")" \
    "legacy mode falls back to UID 1000 when id fails"
  assert_equals "1000" "$(value_from_log ENV_CAPSULE_GID "$log_file")" \
    "legacy mode falls back to GID 1000 when id fails"
  assert_file_contains "$err_file" \
    'cannot detect host UID/GID; using legacy defaults' \
    "legacy defaults emit a warning"
}

test_workdir_precedence() {
  local tdir="$TEST_TMPDIR/workdir"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  local pwd_case="$tdir/pwd-case"
  local expected_pwd_case=""
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  CAPSULE_WORKDIR=/tmp/capsule-first CC_WORKDIR=/tmp/legacy DOCKER_GID=1111 \
    CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true
  assert_equals \
    "/tmp/capsule-first" \
    "$(value_from_log ENV_CAPSULE_WORKDIR "$log_file")" \
    "CAPSULE_WORKDIR takes precedence over CC_WORKDIR"

  : >"$log_file"
  CC_WORKDIR=/tmp/legacy-only DOCKER_GID=1111 CAPSULE_IDMAP=off \
    CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true
  assert_equals \
    "/tmp/legacy-only" \
    "$(value_from_log ENV_CAPSULE_WORKDIR "$log_file")" \
    "CC_WORKDIR is the backward-compatible fallback"

  : >"$log_file"
  mkdir -p "$pwd_case"
  (
    cd "$pwd_case"
    expected_pwd_case="$(pwd -P)"
    DOCKER_GID=1111 CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
      PATH="$mock_bin:$PATH" MOCK_LOG="$log_file" "$SCRIPT_PATH" true
    printf '%s\n' "$expected_pwd_case" >"$tdir/expected_pwd_case"
  )
  expected_pwd_case="$(cat "$tdir/expected_pwd_case")"
  assert_equals \
    "$expected_pwd_case" \
    "$(value_from_log ENV_CAPSULE_WORKDIR "$log_file")" \
    "current directory is the fallback workspace"
}

test_linux_gid_autodetect_from_docker_host() {
  local tdir="$TEST_TMPDIR/linux-detect"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  local sock_path="$tdir/docker.sock"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"
  : >"$sock_path"

  DOCKER_GID= DOCKER_HOST="unix://$sock_path" MOCK_STAT_GID=5678 \
    CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "5678" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "Linux path auto-detects DOCKER_GID from DOCKER_HOST"
}

test_bad_docker_host_falls_back_to_context_socket() {
  local tdir="$TEST_TMPDIR/context-fallback"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  local sock_path="$tdir/context.sock"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"
  : >"$sock_path"

  DOCKER_GID= DOCKER_HOST="unix://$tdir/missing.sock" \
    MOCK_CONTEXT_HOST="unix://$sock_path" MOCK_STAT_GID=6789 \
    CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "6789" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "docker context is the socket fallback when DOCKER_HOST is unusable"
}

test_macos_staff_gid_override() {
  local tdir="$TEST_TMPDIR/darwin-override"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  local sock_path="$tdir/docker.sock"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"
  : >"$sock_path"

  DOCKER_GID= DOCKER_HOST="unix://$sock_path" MOCK_UNAME=Darwin \
    MOCK_STAT_GID=20 CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "991" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "macOS staff gid is remapped to 991"
}

test_default_gid_when_detection_fails() {
  local tdir="$TEST_TMPDIR/defaults"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID= DOCKER_HOST="unix://$tdir/missing.sock" MOCK_STAT_FAIL=1 \
    CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true
  assert_equals "999" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "Linux default DOCKER_GID is 999 when detection fails"

  : >"$log_file"
  DOCKER_GID= DOCKER_HOST="unix://$tdir/missing.sock" MOCK_UNAME=Darwin \
    MOCK_STAT_FAIL=1 CAPSULE_IDMAP=off CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true
  assert_equals "991" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "macOS default DOCKER_GID is 991 when detection fails"
}

test_colima_idmap_mode_on_macos() {
  local tdir="$TEST_TMPDIR/colima-idmap"
  local mock_bin="$tdir/bin"
  local mock_helper="$tdir/helper"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  make_mock_helper "$mock_helper"

  DOCKER_GID= MOCK_UNAME=Darwin MOCK_ID_UID=501 MOCK_ID_GID=20 \
    MOCK_CONTEXT_HOST='unix:///Users/test/.colima/default/docker.sock' \
    MOCK_STAT_GID=20 MOCK_COLIMA_GUEST_PATH=/Users/test/project \
    MOCK_COLIMA_MOUNT_SOURCE=/run/capsule-idmap/colima \
    CAPSULE_WORKDIR=/Users/test/project CAPSULE_IDMAP_HELPER="$mock_helper" \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "1000" "$(value_from_log ENV_CAPSULE_UID "$log_file")" \
    "Colima mode keeps the in-capsule UID fixed"
  assert_equals "1000" "$(value_from_log ENV_CAPSULE_GID "$log_file")" \
    "Colima mode keeps the in-capsule GID fixed"
  assert_equals \
    "/run/capsule-idmap/colima" \
    "$(value_from_log ENV_CAPSULE_MOUNT_SOURCE "$log_file")" \
    "Colima mode injects the guest-side mapped workspace"
  assert_equals "colima" \
    "$(value_from_log ENV_CAPSULE_IDMAP_MODE "$log_file")" \
    "Colima mode is surfaced to Compose"
  assert_equals "991" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "Colima mode preserves the macOS docker gid remap"
}

main() {
  if ! bash -n "$SCRIPT_PATH"; then
    fail "capsule.sh has valid shell syntax"
  else
    pass "capsule.sh has valid shell syntax"
  fi

  test_compose_contract
  test_dockerfile_tooling_contract
  test_dockerfile_uid_gid_contract
  test_entrypoint_contract
  test_helper_contract
  test_build_flag_runs_build_then_runtime
  test_double_dash_keeps_runtime_flags
  test_build_flag_without_runtime_args
  test_plain_runtime_without_args
  test_linux_idmap_mode_uses_mapped_workspace
  test_auto_falls_back_to_legacy_when_helper_fails
  test_force_requires_idmap_support
  test_legacy_compat_aliases_disable_idmap
  test_legacy_defaults_when_id_detection_fails
  test_workdir_precedence
  test_linux_gid_autodetect_from_docker_host
  test_bad_docker_host_falls_back_to_context_socket
  test_macos_staff_gid_override
  test_default_gid_when_detection_fails
  test_colima_idmap_mode_on_macos

  printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  [[ "$FAIL_COUNT" -eq 0 ]]
}

main "$@"
