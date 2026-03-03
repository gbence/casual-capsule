#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
SCRIPT_PATH="$ROOT_DIR/capsule.sh"
COMPOSE_PATH="$ROOT_DIR/compose.yml"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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

assert_log_line() {
  local expected="$1"
  local line_no="$2"
  local file="$3"
  local msg="$4"
  local actual=""
  actual="$(sed -n "${line_no}p" "$file")"
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

  chmod +x "$dir/docker" "$dir/stat" "$dir/uname" "$dir/ls"
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

test_compose_contract() {
  assert_file_contains "$COMPOSE_PATH" 'user: "8888:100"' \
    "compose keeps primary user/group fixed"
  assert_file_contains "$COMPOSE_PATH" '- "${DOCKER_GID:-999}"' \
    "compose injects Docker group from DOCKER_GID"
  assert_file_contains "$COMPOSE_PATH" \
    '${CAPSULE_WORKDIR:-${CC_WORKDIR:-${PWD}}}:/home/workspace' \
    "compose keeps CAPSULE_WORKDIR with compatibility fallback"
}

test_build_flag_runs_build_then_runtime() {
  local tdir="$TEST_TMPDIR/build-flag"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  local expected_build=""
  local expected_run=""
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"

  DOCKER_GID=1111 run_capsule "$mock_bin" "$log_file" --build true

  expected_build="ARGS=compose -f $COMPOSE_PATH --project-directory $ROOT_DIR"
  expected_build="$expected_build build cli"
  expected_run="ARGS=compose -f $COMPOSE_PATH --project-directory $ROOT_DIR"
  expected_run="$expected_run run --rm cli true"

  assert_log_line \
    "$expected_build" \
    3 "$log_file" "build flag runs compose build first"
  assert_log_line \
    "$expected_run" \
    6 "$log_file" "build flag still runs compose runtime"
}

test_double_dash_keeps_runtime_flags() {
  local tdir="$TEST_TMPDIR/double-dash"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  local expected_args=""
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"

  DOCKER_GID=1111 run_capsule "$mock_bin" "$log_file" -- --build true

  expected_args="compose -f $COMPOSE_PATH --project-directory $ROOT_DIR"
  expected_args="$expected_args run --rm cli --build true"

  assert_equals \
    "$expected_args" \
    "$(value_from_log ARGS "$log_file")" \
    "double dash passes build-like flags to runtime command"
}

test_build_flag_without_runtime_args() {
  local tdir="$TEST_TMPDIR/build-no-args"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  local expected_build=""
  local expected_run=""
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"

  DOCKER_GID=1111 run_capsule "$mock_bin" "$log_file" -b

  expected_build="ARGS=compose -f $COMPOSE_PATH --project-directory $ROOT_DIR"
  expected_build="$expected_build build cli"
  expected_run="ARGS=compose -f $COMPOSE_PATH --project-directory $ROOT_DIR"
  expected_run="$expected_run run --rm cli"

  assert_log_line \
    "$expected_build" \
    3 "$log_file" "build flag works without runtime args (build call)"
  assert_log_line \
    "$expected_run" \
    6 "$log_file" "build flag works without runtime args (run call)"
}

test_plain_runtime_without_args() {
  local tdir="$TEST_TMPDIR/run-no-args"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  local expected_run=""
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"

  DOCKER_GID=1111 run_capsule "$mock_bin" "$log_file"

  expected_run="compose -f $COMPOSE_PATH --project-directory $ROOT_DIR"
  expected_run="$expected_run run --rm cli"
  assert_equals \
    "$expected_run" \
    "$(value_from_log ARGS "$log_file")" \
    "plain runtime works without runtime args"
}

test_explicit_docker_gid_passthrough() {
  local tdir="$TEST_TMPDIR/explicit"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"

  DOCKER_GID=4242 CAPSULE_WORKDIR=/tmp/capsule-workdir \
    run_capsule "$mock_bin" "$log_file" bash -lc 'echo ok'

  assert_equals "4242" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "capsule forwards explicit DOCKER_GID"
  assert_equals "/tmp/capsule-workdir" \
    "$(value_from_log ENV_CAPSULE_WORKDIR "$log_file")" \
    "capsule forwards explicit CAPSULE_WORKDIR"
}

test_workdir_precedence() {
  local tdir="$TEST_TMPDIR/workdir"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"

  CAPSULE_WORKDIR=/tmp/capsule-first CC_WORKDIR=/tmp/legacy DOCKER_GID=1111 \
    run_capsule "$mock_bin" "$log_file" true
  assert_equals "/tmp/capsule-first" \
    "$(value_from_log ENV_CAPSULE_WORKDIR "$log_file")" \
    "CAPSULE_WORKDIR takes precedence over CC_WORKDIR"

  : >"$log_file"
  CC_WORKDIR=/tmp/legacy-only DOCKER_GID=1111 \
    run_capsule "$mock_bin" "$log_file" true
  assert_equals "/tmp/legacy-only" \
    "$(value_from_log ENV_CAPSULE_WORKDIR "$log_file")" \
    "CC_WORKDIR is respected as backward-compatible fallback"

  : >"$log_file"
  local pwd_case="$tdir/pwd-case"
  local expected_pwd_case=""
  mkdir -p "$pwd_case"
  (
    cd "$pwd_case"
    expected_pwd_case="$(pwd -P)"
    DOCKER_GID=1111 PATH="$mock_bin:$PATH" MOCK_LOG="$log_file" \
      "$SCRIPT_PATH" true
    printf '%s\n' "$expected_pwd_case" >"$tdir/expected_pwd_case"
  )
  expected_pwd_case="$(cat "$tdir/expected_pwd_case")"
  assert_equals \
    "$expected_pwd_case" \
    "$(value_from_log ENV_CAPSULE_WORKDIR "$log_file")" \
    "current directory is fallback when workdir vars are unset"
}

test_linux_gid_autodetect_from_docker_host() {
  local tdir="$TEST_TMPDIR/linux-detect"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  local sock_path="$tdir/docker.sock"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  : >"$sock_path"

  DOCKER_GID= DOCKER_HOST="unix://$sock_path" MOCK_STAT_GID=5678 \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "5678" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "Linux path auto-detects DOCKER_GID from socket"
}

test_bad_docker_host_falls_back_to_context_socket() {
  local tdir="$TEST_TMPDIR/context-fallback"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  local sock_path="$tdir/context.sock"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  : >"$sock_path"

  DOCKER_GID= DOCKER_HOST="unix://$tdir/missing.sock" \
    MOCK_CONTEXT_HOST="unix://$sock_path" MOCK_STAT_GID=6789 \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "6789" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "capsule ignores unusable DOCKER_HOST and falls back to context"
}

test_macos_staff_gid_override() {
  local tdir="$TEST_TMPDIR/darwin-override"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  local sock_path="$tdir/docker.sock"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"
  : >"$sock_path"

  DOCKER_GID= DOCKER_HOST="unix://$sock_path" MOCK_UNAME=Darwin \
    MOCK_STAT_GID=20 \
    run_capsule "$mock_bin" "$log_file" true

  assert_equals "991" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "macOS staff gid auto-detect is remapped to 991"
}

test_default_gid_when_detection_fails() {
  local tdir="$TEST_TMPDIR/defaults"
  local mock_bin="$tdir/bin"
  local log_file="$tdir/log"
  mkdir -p "$tdir"
  make_mock_bin "$mock_bin"

  DOCKER_GID= DOCKER_HOST="unix://$tdir/missing.sock" MOCK_STAT_FAIL=1 \
    run_capsule "$mock_bin" "$log_file" true
  assert_equals "999" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "Linux default DOCKER_GID is 999 when detection fails"

  : >"$log_file"
  DOCKER_GID= DOCKER_HOST="unix://$tdir/missing.sock" MOCK_UNAME=Darwin \
    MOCK_STAT_FAIL=1 run_capsule "$mock_bin" "$log_file" true
  assert_equals "991" "$(value_from_log ENV_DOCKER_GID "$log_file")" \
    "macOS default DOCKER_GID is 991 when detection fails"
}

main() {
  if ! bash -n "$SCRIPT_PATH"; then
    fail "capsule.sh has valid shell syntax"
  else
    pass "capsule.sh has valid shell syntax"
  fi

  test_compose_contract
  test_build_flag_runs_build_then_runtime
  test_double_dash_keeps_runtime_flags
  test_build_flag_without_runtime_args
  test_plain_runtime_without_args
  test_explicit_docker_gid_passthrough
  test_workdir_precedence
  test_linux_gid_autodetect_from_docker_host
  test_bad_docker_host_falls_back_to_context_socket
  test_macos_staff_gid_override
  test_default_gid_when_detection_fails

  printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  [[ "$FAIL_COUNT" -eq 0 ]]
}

main "$@"
