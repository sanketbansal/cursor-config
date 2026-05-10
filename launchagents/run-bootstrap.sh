#!/bin/sh
# run-bootstrap.sh — Thin wrapper invoked by the system LaunchAgent
# (/Library/LaunchAgents/com.cursor-config.bootstrap.plist).
#
# launchd does not expand `~` in plist files, so we cannot point
# StandardOutPath at a per-user log directly. Instead this wrapper runs in
# the user's session context with a correct $HOME, ensures the log dir
# exists, and execs bootstrap.sh with output redirected to a per-user log.
#
# This script is non-interactive (LaunchAgent provides no controlling TTY),
# so bootstrap.sh's auto-run install prompt skips itself by design.

set -eu

LOGDIR="${HOME}/Library/Logs"
LOGFILE="${LOGDIR}/cursor-config-bootstrap.log"

mkdir -p "${LOGDIR}"

exec /Users/Shared/cursor-config/bootstrap.sh >"${LOGFILE}" 2>&1
