#!/bin/sh
# Claude Code runner — single-source-of-truth adapter between the Cursor
# `claude-code` subagent and the locally installed `claude` CLI.
#
# Subcommands:
#   preflight                                run `claude auth status --json`; emit envelope. Free.
#   probe                                    preflight + 1-token round-trip on the target model. Cheap.
#   run <prompt_file> [budget] [model] [effort] [perm]
#                                            execute the real task; capture files modified via git diff.
#
# Output contract: exactly one line of JSON on stdout. All diagnostics go to stderr.
# Exit code: 0 = envelope emitted (success OR known failure); 2 = internal error (no envelope).
#
# Environment overrides:
#   CLAUDE_CODE_RUNNER_MODEL    override target model (default: read from ~/.claude/settings.json)
#   CLAUDE_CODE_RUNNER_BUDGET   override --max-budget-usd (default: 1.0)
#   CLAUDE_CODE_RUNNER_EFFORT   override --effort (default: high)
#   CLAUDE_CODE_RUNNER_PERM     override --permission-mode (default: acceptEdits)
#   CLAUDE_CODE_RUNNER_TIMEOUT  wall-clock seconds before the call is killed (default: 600)
#   CLAUDE_CODE_RUNNER_CWD      cwd for `run` (default: $PWD)

set -eu

# Cursor's Shell tool does not inherit a user's interactive PATH; add the
# canonical install locations so `claude` resolves regardless of caller.
export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:${PATH:-/usr/bin:/bin}"

# -------- defaults --------
DEFAULT_BUDGET="1.0"
DEFAULT_EFFORT="high"
DEFAULT_PERM="acceptEdits"
DEFAULT_TIMEOUT="600"
PROBE_PROMPT="reply: ready"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# -------- helpers --------

# Print to stderr.
_log() {
    printf '%s\n' "$*" >&2
}

# Emit a single line of JSON on stdout from a python heredoc. Caller exports
# every variable it wants to interpolate via os.environ. Always exit 0 after
# emit so the calling shell can decide its own exit status.
_emit_envelope() {
    /usr/bin/env python3 - <<'PYEOF'
import json, os, sys

def _get_str(key, default=""):
    v = os.environ.get(key)
    return default if v is None or v == "" else v

def _get_int(key, default=0):
    v = os.environ.get(key, "")
    try:
        return int(v)
    except (TypeError, ValueError):
        return default

def _get_json(key, default=None):
    v = os.environ.get(key, "")
    if not v:
        return default
    try:
        return json.loads(v)
    except (TypeError, ValueError):
        return default

available = os.environ.get("ENV_AVAILABLE", "false").lower() == "true"
reason = os.environ.get("ENV_REASON") or None

auth = _get_json("ENV_AUTH_JSON", None)

result_raw = os.environ.get("ENV_RESULT", "")
result_format = os.environ.get("ENV_RESULT_FORMAT", "") or None
if result_format == "json" and result_raw:
    try:
        result = json.loads(result_raw)
    except (TypeError, ValueError):
        result = result_raw
        result_format = "text"
elif result_format == "text":
    result = result_raw
else:
    result = None
    result_format = None

files_modified = _get_json("ENV_FILES_MODIFIED_JSON", [])
if not isinstance(files_modified, list):
    files_modified = []

elapsed_ms = _get_int("ENV_ELAPSED_MS", 0)
cli_version = _get_str("ENV_CLI_VERSION", "") or None
exit_code = _get_int("ENV_EXIT_CODE", 0)
stderr_tail = os.environ.get("ENV_STDERR_TAIL", "") or None

envelope = {
    "available": available,
    "reason": reason,
    "auth": auth,
    "result": result,
    "result_format": result_format,
    "files_modified": files_modified,
    "elapsed_ms": elapsed_ms,
    "cli_version": cli_version,
    "exit_code": exit_code,
    "stderr_tail": stderr_tail,
}

sys.stdout.write(json.dumps(envelope, separators=(",", ":")) + "\n")
sys.stdout.flush()
PYEOF
}

# Classify a stderr/stdout combined blob into a canonical reason string.
# Echoes the reason on stdout. Returns "" (empty string) when no pattern matched.
_classify_failure() {
    _blob="$1"
    _lc=$(printf '%s' "$_blob" | tr '[:upper:]' '[:lower:]')
    case "$_lc" in
        *"reached maximum budget"*|*"max budget"*|*"max-budget"*|*"error_max_budget_usd"*|*"budget exceed"*|*"budget cap"*|*"max_budget"*)
            printf '%s' "budget_exceeded"
            ;;
        *"rate limit"*|*"rate-limit"*|*"rate_limit"*|*"too many requests"*|*"429"*|*"usage cap"*|*"weekly limit"*|*"5-hour"*|*"5 hour"*|*quota*|*overloaded*)
            printf '%s' "rate_limit"
            ;;
        *"not authenticated"*|*"not logged in"*|*"please log in"*|*"401"*|*"unauthorized"*|*"please authenticate"*)
            printf '%s' "not_logged_in"
            ;;
        *"auth"*"error"*|*"authentication"*"failed"*)
            printf '%s' "auth_error"
            ;;
        *)
            printf '%s' ""
            ;;
    esac
}

# Parse a JSON blob from `claude -p --output-format json` and detect semantic
# failure. The CLI exits non-zero on soft errors (budget overrun, etc.) but
# the actionable signal lives inside the JSON, not in stderr.
#
# Echoes the canonical reason on stdout, or empty string when the JSON
# indicates success / cannot be parsed. Reads JSON from stdin.
_classify_json_result() {
    /usr/bin/env python3 - <<'PYEOF'
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    d = json.loads(raw)
except (ValueError, TypeError):
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
if not d.get("is_error"):
    sys.exit(0)
subtype = str(d.get("subtype") or "").lower()
errors = d.get("errors") or []
errors_text = " ".join(str(e) for e in errors).lower() if isinstance(errors, list) else str(errors).lower()
blob = subtype + " " + errors_text
if "max_budget_usd" in subtype or "budget" in blob or "max budget" in blob:
    print("budget_exceeded"); sys.exit(0)
if "rate" in blob or "quota" in blob or "429" in blob or "overloaded" in blob or "usage cap" in blob:
    print("rate_limit"); sys.exit(0)
if "auth" in blob or "401" in blob or "unauthor" in blob:
    print("not_logged_in"); sys.exit(0)
if "timeout" in blob or "timed out" in blob:
    print("timeout"); sys.exit(0)
print("unknown_error"); sys.exit(0)
PYEOF
}

# Read `claude` CLI version, or empty string if not installed.
_cli_version() {
    if ! command -v claude >/dev/null 2>&1; then
        printf '%s' ""
        return 0
    fi
    claude --version 2>/dev/null | awk 'NR==1 {print $1; exit}'
}

# Read the user's default model from ~/.claude/settings.json, or empty.
_default_model() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        printf '%s' ""
        return 0
    fi
    if command -v jq >/dev/null 2>&1; then
        jq -r '.model // ""' "$SETTINGS_FILE" 2>/dev/null
        return 0
    fi
    /usr/bin/env python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("model", "") or "")
except Exception:
    print("")
PYEOF
}

# Run `claude auth status --json`, parse to inner JSON, store in ENV_AUTH_JSON.
# Sets ENV_AVAILABLE / ENV_REASON when not logged in or unparseable.
# Returns 0 on success (logged in), 1 on any failure to obtain a "loggedIn:true".
_do_preflight() {
    if ! command -v claude >/dev/null 2>&1; then
        ENV_AVAILABLE="false"
        ENV_REASON="not_installed"
        ENV_AUTH_JSON=""
        export ENV_AVAILABLE ENV_REASON ENV_AUTH_JSON
        return 1
    fi

    _auth_out=$(claude auth status --json 2>/dev/null || true)
    if [ -z "$_auth_out" ]; then
        ENV_AVAILABLE="false"
        ENV_REASON="auth_error"
        ENV_AUTH_JSON=""
        export ENV_AVAILABLE ENV_REASON ENV_AUTH_JSON
        return 1
    fi

    _logged_in=""
    if command -v jq >/dev/null 2>&1; then
        _logged_in=$(printf '%s' "$_auth_out" | jq -r '.loggedIn // false' 2>/dev/null || printf '%s' "false")
    else
        _logged_in=$(printf '%s' "$_auth_out" | /usr/bin/env python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(str(d.get("loggedIn", False)).lower())
except Exception:
    print("false")
' 2>/dev/null || printf '%s' "false")
    fi

    ENV_AUTH_JSON="$_auth_out"
    export ENV_AUTH_JSON

    if [ "$_logged_in" != "true" ]; then
        ENV_AVAILABLE="false"
        ENV_REASON="not_logged_in"
        export ENV_AVAILABLE ENV_REASON
        return 1
    fi

    ENV_AVAILABLE="true"
    ENV_REASON=""
    export ENV_AVAILABLE ENV_REASON
    return 0
}

# Portable wall-clock timeout. macOS does not ship `timeout`.
# Usage: _bounded_run <seconds> <stdout_file> <stderr_file> <cmd...>
# Returns the child's exit code, or 124 on timeout.
_bounded_run() {
    _secs="$1"
    _out="$2"
    _err="$3"
    shift 3

    "$@" >"$_out" 2>"$_err" &
    _child_pid=$!

    (
        _waited=0
        while [ "$_waited" -lt "$_secs" ]; do
            if ! kill -0 "$_child_pid" 2>/dev/null; then
                exit 0
            fi
            sleep 1
            _waited=$((_waited + 1))
        done
        if kill -0 "$_child_pid" 2>/dev/null; then
            kill -TERM "$_child_pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$_child_pid" 2>/dev/null || true
        fi
    ) &
    _killer_pid=$!

    _rc=0
    wait "$_child_pid" 2>/dev/null || _rc=$?
    kill "$_killer_pid" 2>/dev/null || true
    wait "$_killer_pid" 2>/dev/null || true

    if [ "$_rc" -eq 143 ] || [ "$_rc" -eq 137 ]; then
        return 124
    fi
    return "$_rc"
}

# Snapshot tracked + untracked files under the given dir. Used so we can
# diff before / after a `run` and compute `files_modified` even when the
# user is not on a clean git working tree to start with.
_git_state_snapshot() {
    _dir="$1"
    if [ ! -d "$_dir/.git" ] && ! git -C "$_dir" rev-parse --git-dir >/dev/null 2>&1; then
        printf ''
        return 0
    fi
    git -C "$_dir" status --porcelain=v1 2>/dev/null | sort || true
}

# Diff two porcelain snapshots and emit a JSON array of changed paths.
_files_modified_json() {
    _before_file="$1"
    _after_file="$2"
    /usr/bin/env python3 - "$_before_file" "$_after_file" <<'PYEOF'
import json, sys

def parse(path):
    out = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.rstrip("\n")
                if len(line) < 4:
                    continue
                status = line[:2]
                rest = line[3:]
                if " -> " in rest:
                    rest = rest.split(" -> ")[-1]
                out[rest.strip()] = status
    except Exception:
        pass
    return out

before = parse(sys.argv[1])
after = parse(sys.argv[2])
changed = sorted(set(p for p, s in after.items() if before.get(p) != s) | set(before) - set(after))
print(json.dumps(changed))
PYEOF
}

# -------- subcommands --------

_sub_preflight() {
    ENV_AVAILABLE="false"
    ENV_REASON=""
    ENV_AUTH_JSON=""
    ENV_RESULT=""
    ENV_RESULT_FORMAT=""
    ENV_FILES_MODIFIED_JSON="[]"
    ENV_ELAPSED_MS="0"
    ENV_CLI_VERSION="$(_cli_version)"
    ENV_EXIT_CODE="0"
    ENV_STDERR_TAIL=""
    export ENV_AVAILABLE ENV_REASON ENV_AUTH_JSON ENV_RESULT ENV_RESULT_FORMAT \
        ENV_FILES_MODIFIED_JSON ENV_ELAPSED_MS ENV_CLI_VERSION ENV_EXIT_CODE ENV_STDERR_TAIL

    _start_ms=$(date +%s)
    _do_preflight || true
    _end_ms=$(date +%s)
    ENV_ELAPSED_MS=$(( (_end_ms - _start_ms) * 1000 ))
    export ENV_ELAPSED_MS

    _emit_envelope
    return 0
}

_sub_probe() {
    ENV_AVAILABLE="false"
    ENV_REASON=""
    ENV_AUTH_JSON=""
    ENV_RESULT=""
    ENV_RESULT_FORMAT=""
    ENV_FILES_MODIFIED_JSON="[]"
    ENV_ELAPSED_MS="0"
    ENV_CLI_VERSION="$(_cli_version)"
    ENV_EXIT_CODE="0"
    ENV_STDERR_TAIL=""
    export ENV_AVAILABLE ENV_REASON ENV_AUTH_JSON ENV_RESULT ENV_RESULT_FORMAT \
        ENV_FILES_MODIFIED_JSON ENV_ELAPSED_MS ENV_CLI_VERSION ENV_EXIT_CODE ENV_STDERR_TAIL

    _start_ms=$(date +%s)

    if ! _do_preflight; then
        _end_ms=$(date +%s)
        ENV_ELAPSED_MS=$(( (_end_ms - _start_ms) * 1000 ))
        export ENV_ELAPSED_MS
        _emit_envelope
        return 0
    fi

    _model="${CLAUDE_CODE_RUNNER_MODEL:-$(_default_model)}"
    _timeout="${CLAUDE_CODE_RUNNER_TIMEOUT:-$DEFAULT_TIMEOUT}"

    _tmpdir=$(mktemp -d)
    trap 'rm -rf "$_tmpdir"' EXIT INT TERM
    _out="$_tmpdir/out"
    _err="$_tmpdir/err"

    # No `--max-budget-usd` on the probe: one token round-trips fine without
    # one, and the CLI computes a notional cost that can trip even a $0.10
    # cap on opus (fresh cache fill is charged at full rate). The probe's
    # purpose is "did the model respond non-error", not cost control.
    set +e
    if [ -n "$_model" ]; then
        _bounded_run "$_timeout" "$_out" "$_err" \
            claude -p "$PROBE_PROMPT" \
            --output-format json \
            --no-session-persistence \
            --effort low \
            --model "$_model"
    else
        _bounded_run "$_timeout" "$_out" "$_err" \
            claude -p "$PROBE_PROMPT" \
            --output-format json \
            --no-session-persistence \
            --effort low
    fi
    _rc=$?
    set -e

    _end_ms=$(date +%s)
    ENV_ELAPSED_MS=$(( (_end_ms - _start_ms) * 1000 ))
    ENV_EXIT_CODE="$_rc"
    export ENV_ELAPSED_MS ENV_EXIT_CODE

    _err_blob=$(tail -c 2048 "$_err" 2>/dev/null || printf '')
    _out_blob=$(cat "$_out" 2>/dev/null || printf '')

    if [ "$_rc" -eq 124 ]; then
        ENV_AVAILABLE="false"
        ENV_REASON="timeout"
        ENV_STDERR_TAIL="$_err_blob"
        export ENV_AVAILABLE ENV_REASON ENV_STDERR_TAIL
        _emit_envelope
        return 0
    fi

    # JSON-mode signal wins over exit code: the CLI exits non-zero on soft
    # errors (budget, rate-limit) but encodes the actionable info inside
    # the JSON payload. Check that first, then fall back to stderr regex.
    _json_reason=$(printf '%s' "$_out_blob" | _classify_json_result)
    if [ -n "$_json_reason" ]; then
        ENV_AVAILABLE="false"
        ENV_REASON="$_json_reason"
        ENV_STDERR_TAIL="$_err_blob"
        export ENV_AVAILABLE ENV_REASON ENV_STDERR_TAIL
        _emit_envelope
        return 0
    fi

    if [ "$_rc" -ne 0 ]; then
        _reason=$(_classify_failure "${_err_blob}
${_out_blob}")
        if [ -z "$_reason" ]; then _reason="unknown_error"; fi
        ENV_AVAILABLE="false"
        ENV_REASON="$_reason"
        ENV_STDERR_TAIL="$_err_blob"
        export ENV_AVAILABLE ENV_REASON ENV_STDERR_TAIL
        _emit_envelope
        return 0
    fi

    ENV_AVAILABLE="true"
    ENV_REASON=""
    ENV_RESULT="$_out_blob"
    ENV_RESULT_FORMAT="json"
    export ENV_AVAILABLE ENV_REASON ENV_RESULT ENV_RESULT_FORMAT
    _emit_envelope
    return 0
}

_sub_run() {
    _prompt_file="${1:-}"
    if [ -z "$_prompt_file" ] || [ ! -f "$_prompt_file" ]; then
        _log "run: missing or unreadable prompt file: '$_prompt_file'"
        return 2
    fi
    _budget="${2:-${CLAUDE_CODE_RUNNER_BUDGET:-$DEFAULT_BUDGET}}"
    _model_arg="${3:-${CLAUDE_CODE_RUNNER_MODEL:-}}"
    _effort="${4:-${CLAUDE_CODE_RUNNER_EFFORT:-$DEFAULT_EFFORT}}"
    _perm="${5:-${CLAUDE_CODE_RUNNER_PERM:-$DEFAULT_PERM}}"
    _timeout="${CLAUDE_CODE_RUNNER_TIMEOUT:-$DEFAULT_TIMEOUT}"

    _model="$_model_arg"
    if [ -z "$_model" ] || [ "$_model" = "auto" ]; then
        _model="$(_default_model)"
    fi

    _work_dir="${CLAUDE_CODE_RUNNER_CWD:-$PWD}"
    if [ ! -d "$_work_dir" ]; then
        _log "run: cwd does not exist: '$_work_dir'"
        return 2
    fi

    ENV_AVAILABLE="false"
    ENV_REASON=""
    ENV_AUTH_JSON=""
    ENV_RESULT=""
    ENV_RESULT_FORMAT=""
    ENV_FILES_MODIFIED_JSON="[]"
    ENV_ELAPSED_MS="0"
    ENV_CLI_VERSION="$(_cli_version)"
    ENV_EXIT_CODE="0"
    ENV_STDERR_TAIL=""
    export ENV_AVAILABLE ENV_REASON ENV_AUTH_JSON ENV_RESULT ENV_RESULT_FORMAT \
        ENV_FILES_MODIFIED_JSON ENV_ELAPSED_MS ENV_CLI_VERSION ENV_EXIT_CODE ENV_STDERR_TAIL

    _start_ms=$(date +%s)

    if ! _do_preflight; then
        _end_ms=$(date +%s)
        ENV_ELAPSED_MS=$(( (_end_ms - _start_ms) * 1000 ))
        export ENV_ELAPSED_MS
        _emit_envelope
        return 0
    fi

    _tmpdir=$(mktemp -d)
    trap 'rm -rf "$_tmpdir"' EXIT INT TERM
    _out="$_tmpdir/out"
    _err="$_tmpdir/err"
    _before="$_tmpdir/git_before"
    _after="$_tmpdir/git_after"

    _git_state_snapshot "$_work_dir" >"$_before" 2>/dev/null || true

    _prompt_body=$(cat "$_prompt_file")

    set +e
    cd "$_work_dir" || { _log "run: cd to '$_work_dir' failed"; return 2; }
    if [ -n "$_model" ]; then
        _bounded_run "$_timeout" "$_out" "$_err" \
            claude -p "$_prompt_body" \
            --output-format json \
            --max-budget-usd "$_budget" \
            --no-session-persistence \
            --model "$_model" \
            --effort "$_effort" \
            --permission-mode "$_perm" \
            --add-dir "$_work_dir"
    else
        _bounded_run "$_timeout" "$_out" "$_err" \
            claude -p "$_prompt_body" \
            --output-format json \
            --max-budget-usd "$_budget" \
            --no-session-persistence \
            --effort "$_effort" \
            --permission-mode "$_perm" \
            --add-dir "$_work_dir"
    fi
    _rc=$?
    set -e

    _git_state_snapshot "$_work_dir" >"$_after" 2>/dev/null || true
    ENV_FILES_MODIFIED_JSON=$(_files_modified_json "$_before" "$_after")
    export ENV_FILES_MODIFIED_JSON

    _end_ms=$(date +%s)
    ENV_ELAPSED_MS=$(( (_end_ms - _start_ms) * 1000 ))
    ENV_EXIT_CODE="$_rc"
    export ENV_ELAPSED_MS ENV_EXIT_CODE

    _err_blob=$(tail -c 2048 "$_err" 2>/dev/null || printf '')
    _out_blob=$(cat "$_out" 2>/dev/null || printf '')

    if [ "$_rc" -eq 124 ]; then
        ENV_AVAILABLE="false"
        ENV_REASON="timeout"
        ENV_STDERR_TAIL="$_err_blob"
        export ENV_AVAILABLE ENV_REASON ENV_STDERR_TAIL
        _emit_envelope
        return 0
    fi

    _json_reason=$(printf '%s' "$_out_blob" | _classify_json_result)
    if [ -n "$_json_reason" ]; then
        ENV_AVAILABLE="false"
        ENV_REASON="$_json_reason"
        ENV_RESULT="$_out_blob"
        ENV_RESULT_FORMAT="json"
        ENV_STDERR_TAIL="$_err_blob"
        export ENV_AVAILABLE ENV_REASON ENV_RESULT ENV_RESULT_FORMAT ENV_STDERR_TAIL
        _emit_envelope
        return 0
    fi

    if [ "$_rc" -ne 0 ]; then
        _reason=$(_classify_failure "${_err_blob}
${_out_blob}")
        if [ -z "$_reason" ]; then _reason="unknown_error"; fi
        ENV_AVAILABLE="false"
        ENV_REASON="$_reason"
        ENV_STDERR_TAIL="$_err_blob"
        export ENV_AVAILABLE ENV_REASON ENV_STDERR_TAIL
        _emit_envelope
        return 0
    fi

    ENV_AVAILABLE="true"
    ENV_REASON=""
    ENV_RESULT="$_out_blob"
    ENV_RESULT_FORMAT="json"
    export ENV_AVAILABLE ENV_REASON ENV_RESULT ENV_RESULT_FORMAT
    _emit_envelope
    return 0
}

# -------- dispatch --------

_cmd="${1:-}"
if [ -n "$_cmd" ]; then
    shift
fi

case "$_cmd" in
    preflight)
        _sub_preflight "$@"
        ;;
    probe)
        _sub_probe "$@"
        ;;
    run)
        _sub_run "$@"
        ;;
    ""|-h|--help|help)
        _log "usage: $0 {preflight|probe|run <prompt_file> [budget] [model] [effort] [perm]}"
        exit 2
        ;;
    *)
        _log "unknown subcommand: '$_cmd'"
        _log "usage: $0 {preflight|probe|run <prompt_file> [budget] [model] [effort] [perm]}"
        exit 2
        ;;
esac
