#!/bin/sh
# uninstall-autorun.sh — Remove the system LaunchAgent that auto-runs
# bootstrap.sh at every user login.
#
# Self-elevates to sudo, unloads the agent for the invoking user, then
# deletes the plist from /Library/LaunchAgents/. Idempotent — running it
# twice is fine. Per-user log files at ~/Library/Logs/cursor-config-bootstrap.log
# are intentionally left in place; users can delete them manually.

set -eu

DEST_PLIST="/Library/LaunchAgents/com.cursor-config.bootstrap.plist"
LABEL="com.cursor-config.bootstrap"

if [ "$(id -u)" -ne 0 ]; then
    echo "Need root to remove the LaunchAgent from /Library/LaunchAgents/."
    echo "Re-running with sudo (you may be prompted for your password)."
    exec sudo "$0" "$@"
fi

TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_UID=$(id -u "${TARGET_USER}")

if [ ! -f "${DEST_PLIST}" ]; then
    echo "ok     ${DEST_PLIST} not found; nothing to uninstall."
    exit 0
fi

# Bootout the agent for the invoking user. Non-fatal: it is fine if the
# agent is not currently loaded.
launchctl bootout "gui/${TARGET_UID}/${LABEL}" 2>/dev/null || true
echo "bootout gui/${TARGET_UID}/${LABEL} (non-fatal if not loaded)."

rm -f "${DEST_PLIST}"
echo "removed ${DEST_PLIST}."

echo
echo "auto-run uninstall complete."
echo "future logins on this Mac will not auto-run bootstrap.sh."
echo "run /Users/Shared/cursor-config/bootstrap.sh manually as needed."
echo "per-user logs at ~/Library/Logs/cursor-config-bootstrap.log are left in place."
