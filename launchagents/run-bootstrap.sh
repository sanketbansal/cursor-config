#!/bin/sh
# run-bootstrap.sh — Thin wrapper invoked by the system LaunchAgent
# (/Library/LaunchAgents/com.cursor-config.bootstrap.plist).
#
# launchd does not expand `~` in plist files, so we cannot point
# StandardOutPath at a per-user log directly. Instead this wrapper runs in
# the user's session context with a correct $HOME, ensures the log dir
# exists, refreshes the canonical repo via `git pull --ff-only` (fail-soft),
# and execs bootstrap.sh with output redirected to a per-user log.
#
# This script is non-interactive (LaunchAgent provides no controlling TTY),
# so bootstrap.sh's auto-run install prompt skips itself by design.

set -eu

LOGDIR="${HOME}/Library/Logs"
LOGFILE="${LOGDIR}/cursor-config-bootstrap.log"
CANONICAL_DIR="/Users/Shared/cursor-config"

mkdir -p "${LOGDIR}"

# Refresh the canonical working copy from its git remote before copying it
# out. Fail soft on purpose: --ff-only refuses diverged histories, offline
# Macs have no network, and secondary macOS users may lack write access to
# the repo — in every such case we log and bootstrap the existing tree
# rather than blocking login sync. Never resets or discards local edits.
{
    if git -C "${CANONICAL_DIR}" remote get-url origin >/dev/null 2>&1; then
        git -C "${CANONICAL_DIR}" pull --ff-only 2>&1 || echo "warn: git pull failed; bootstrapping existing tree."
    else
        echo "info: no git remote configured; skipping pull."
    fi
} >"${LOGFILE}" 2>&1

exec /Users/Shared/cursor-config/bootstrap.sh >>"${LOGFILE}" 2>&1
