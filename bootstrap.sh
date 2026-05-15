#!/bin/sh
# bootstrap.sh — Copy this canonical cursor-config repo into the current
# macOS user's ~/.cursor/ directory.
#
# Run once per user account (each user runs it themselves). Safe to re-run:
# every step is an idempotent overwrite, never a delete-then-write.
#
# Why copy and not symlink? Cursor reads agents, skills, rules, hooks, and
# standards directly from real files under ~/.cursor/ — that is the working
# layout users already have. Earlier versions of this script symlinked from
# /Users/Shared/cursor-config/ into ~/.cursor/, but that broke the moment a
# user already had real files at ~/.cursor/{agents,skills,hooks}/ (the
# default state on most installs). Copy-everything mirrors what is already
# working. The trade-off — local edits under ~/.cursor/ no longer propagate
# back to canonical automatically — is intentional: edit in
# /Users/Shared/cursor-config/ and re-run this script (or rely on the
# auto-run-on-login LaunchAgent at launchagents/install-autorun.sh) to push
# the change out.
#
# Never touches Cursor-managed locations (~/.cursor/skills-cursor/) or
# per-machine state directories (~/.cursor/projects/, ~/.cursor/plans/,
# ~/.cursor/extensions/, ~/.cursor/plugins/cache/).

set -eu

CANONICAL_DIR="/Users/Shared/cursor-config"

if [ ! -d "${CANONICAL_DIR}" ]; then
    echo "error: canonical dir ${CANONICAL_DIR} does not exist." >&2
    echo "       clone the cursor-config repo to ${CANONICAL_DIR} before running bootstrap." >&2
    exit 1
fi

if [ ! -d "${CANONICAL_DIR}/.git" ]; then
    echo "error: ${CANONICAL_DIR} is not a git working tree." >&2
    echo "       refusing to sync from an unversioned dir; run 'git init' inside ${CANONICAL_DIR} first." >&2
    exit 1
fi

TARGET_HOME="${HOME}/.cursor"
mkdir -p "${TARGET_HOME}"

# Helper: copy a directory subtree from canonical → target. Idempotent
# overwrite of every file in the subtree; files present at the destination
# but not in canonical are left in place (no stale-file deletion).
# Usage: sync_tree <repo-relpath> <target-relpath>
sync_tree() {
    src="${CANONICAL_DIR}/$1"
    dst="${TARGET_HOME}/$2"

    if [ ! -d "${src}" ]; then
        echo "skip   $1: missing in canonical."
        return 0
    fi

    mkdir -p "${dst}"
    # cp -R "${src}/." "${dst}/" copies the *contents* of src into dst,
    # giving merge-overwrite semantics regardless of whether dst already
    # exists. Avoids the BSD-cp quirk where `cp -R src dst/` nests src/src
    # inside an existing dst.
    cp -R -f "${src}/." "${dst}/"
    echo "synced $1/ -> ${dst}/"
}

# Helper: copy a single file from canonical → target.
# Usage: sync_file <repo-relpath> <target-relpath>
sync_file() {
    src="${CANONICAL_DIR}/$1"
    dst="${TARGET_HOME}/$2"

    if [ ! -f "${src}" ]; then
        echo "skip   $1: missing in canonical."
        return 0
    fi

    mkdir -p "$(dirname "${dst}")"
    cp -f "${src}" "${dst}"
    echo "synced $1 -> ${dst}"
}

# 1. Copy the four canonical subtrees.
sync_tree "agents"    "agents"
sync_tree "skills"    "skills"
sync_tree "rules"     "rules"
sync_tree "hooks"     "hooks"

# 2. Copy the standalone standards docs into ~/.cursor/ at the top level
#    (this is where the engineering-standards skill and the User Rules
#    paste-source point at).
sync_file "standards/engineering-standards.md"   "engineering-standards.md"
sync_file "standards/scalable-backend-design.md" "scalable-backend-design.md"

# 3. Copy the top-level dotfiles. hooks.json is the Cursor hook registration
#    consumed by the subagentStop relay.
sync_file "hooks.json"     "hooks.json"

# 4. Refresh +x on every script under hooks/ and on the claude-code runner.
if [ -d "${TARGET_HOME}/hooks" ]; then
    find "${TARGET_HOME}/hooks/" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \; 2>/dev/null || true
    echo "chmod  hooks/* (+x) refreshed."
fi
if [ -f "${TARGET_HOME}/agents/claude-code.runner.sh" ]; then
    chmod +x "${TARGET_HOME}/agents/claude-code.runner.sh" 2>/dev/null || true
    echo "chmod  agents/claude-code.runner.sh (+x) refreshed."
fi

# 5. Optionally offer to install the system LaunchAgent that auto-runs
#    bootstrap.sh at every user login on this Mac (covers all current
#    and future macOS users via /Library/LaunchAgents/).
#
#    Skip silently when:
#      - CURSOR_CONFIG_NO_AUTORUN=1 is set (the LaunchAgent's own wrapper
#        sets this so the auto-run invocation never re-prompts).
#      - Stdin is not a tty (cron, CI, redirected input).
#      - The LaunchAgent plist is already installed at the system path.
LAUNCHAGENT_DEST="/Library/LaunchAgents/com.cursor-config.bootstrap.plist"
INSTALL_AUTORUN="${CANONICAL_DIR}/launchagents/install-autorun.sh"

if [ "${CURSOR_CONFIG_NO_AUTORUN:-0}" = "1" ]; then
    :
elif [ -f "${LAUNCHAGENT_DEST}" ]; then
    echo "ok     auto-run already installed at ${LAUNCHAGENT_DEST}; skipping prompt."
elif [ ! -t 0 ]; then
    :
elif [ ! -x "${INSTALL_AUTORUN}" ]; then
    echo "skip   ${INSTALL_AUTORUN} missing or not executable; skipping prompt."
else
    echo
    echo "Optional: install auto-run-on-login for every macOS user on this Mac?"
    echo "Once installed, every current and future user auto-runs bootstrap.sh"
    echo "at login. Logs go to ~/Library/Logs/cursor-config-bootstrap.log."
    echo "To disable later: sudo bash ${CANONICAL_DIR}/launchagents/uninstall-autorun.sh"
    printf "Install now? [y/N] "
    read autorun_answer || autorun_answer=""
    case "${autorun_answer}" in
        y|Y|yes|YES)
            "${INSTALL_AUTORUN}"
            ;;
        *)
            echo "skipped. Run ${INSTALL_AUTORUN} later if you change your mind."
            ;;
    esac
fi

echo
echo "bootstrap complete. ~/.cursor/ now mirrors ${CANONICAL_DIR}."
echo "to update later: cd ${CANONICAL_DIR} && git pull && bash bootstrap.sh"
