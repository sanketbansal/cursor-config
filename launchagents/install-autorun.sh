#!/bin/sh
# install-autorun.sh — Install the system LaunchAgent that auto-runs
# bootstrap.sh for every user at every login.
#
# Self-elevates to sudo. Copies the canonical plist into
# /Library/LaunchAgents/, sets root:wheel 644 (the values macOS expects
# for system-scope LaunchAgents), and bootstraps the agent for the
# invoking user's GUI session so it loads immediately. Idempotent —
# safe to re-run.

set -eu

CANONICAL_PLIST="/Users/Shared/cursor-config/launchagents/com.cursor-config.bootstrap.plist"
DEST_PLIST="/Library/LaunchAgents/com.cursor-config.bootstrap.plist"
LABEL="com.cursor-config.bootstrap"

if [ ! -f "${CANONICAL_PLIST}" ]; then
    echo "error: canonical plist missing at ${CANONICAL_PLIST}" >&2
    echo "       expected /Users/Shared/cursor-config to contain the launchagents/ dir." >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Need root to install the LaunchAgent into /Library/LaunchAgents/."
    echo "Re-running with sudo (you may be prompted for your password)."
    exec sudo "$0" "$@"
fi

TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_UID=$(id -u "${TARGET_USER}")

# Idempotency: if the destination already exists and is byte-identical,
# the agent is already correctly installed. Confirm it's loaded; if not,
# re-bootstrap.
if [ -f "${DEST_PLIST}" ] && cmp -s "${CANONICAL_PLIST}" "${DEST_PLIST}"; then
    echo "ok     ${DEST_PLIST} already byte-identical to canonical."
    if launchctl print "gui/${TARGET_UID}/${LABEL}" >/dev/null 2>&1; then
        echo "ok     agent already loaded for gui/${TARGET_UID}."
        echo "auto-run install: nothing to do."
        exit 0
    fi
    echo "info   plist matches but agent is not loaded; bootstrapping now."
else
    cp "${CANONICAL_PLIST}" "${DEST_PLIST}"
    chown root:wheel "${DEST_PLIST}"
    chmod 644 "${DEST_PLIST}"
    echo "copied ${CANONICAL_PLIST} -> ${DEST_PLIST} (root:wheel 644)."
fi

# If an old version of the agent is already loaded, bootout first so
# bootstrap can pick up the new plist. Non-fatal: it is fine if the agent
# is not loaded yet.
launchctl bootout "gui/${TARGET_UID}/${LABEL}" 2>/dev/null || true

# Bootstrap the agent for the invoking user's GUI session. This makes
# the auto-run live immediately for the current login. Other users on
# this Mac pick it up at their next login automatically because
# /Library/LaunchAgents/ is system scope.
if launchctl bootstrap "gui/${TARGET_UID}" "${DEST_PLIST}" 2>/dev/null; then
    echo "loaded gui/${TARGET_UID}/${LABEL}."
else
    echo "note   launchctl bootstrap returned non-zero. The plist will load"
    echo "       at the next login regardless. (Reasons this can happen:"
    echo "       running outside a GUI session, or no Aqua session for the"
    echo "       target uid.)"
fi

echo
echo "auto-run install complete."
echo "future logins on this Mac (every user) auto-run bootstrap.sh."
echo "log location per user: ~/Library/Logs/cursor-config-bootstrap.log"
echo "to disable: sudo bash /Users/Shared/cursor-config/launchagents/uninstall-autorun.sh"
