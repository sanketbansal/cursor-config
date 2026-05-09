#!/bin/sh
# bootstrap.sh — Idempotently link this canonical cursor-config repo into the
# current macOS user's ~/.cursor/ directory.
#
# Run once per user account (each user runs it themselves). Safe to re-run.
# Never touches Cursor-managed locations (~/.cursor/skills-cursor/) or per-machine
# state directories (~/.cursor/projects/, ~/.cursor/plans/, ~/.cursor/extensions/,
# ~/.cursor/plugins/cache/).
#
# Contract per plan section 7.4.

set -eu

# 1. Locate canonical source.
CANONICAL_DIR="/Users/Shared/cursor-config"

if [ ! -d "${CANONICAL_DIR}" ]; then
    echo "error: canonical dir ${CANONICAL_DIR} does not exist." >&2
    echo "       clone the cursor-config repo to ${CANONICAL_DIR} before running bootstrap." >&2
    exit 1
fi

if [ ! -d "${CANONICAL_DIR}/.git" ]; then
    echo "error: ${CANONICAL_DIR} is not a git working tree." >&2
    echo "       refusing to symlink an unversioned dir; run 'git init' inside ${CANONICAL_DIR} first." >&2
    exit 1
fi

# 2. Ensure the user's ~/.cursor/ directory exists.
TARGET_HOME="${HOME}/.cursor"
mkdir -p "${TARGET_HOME}"

# Helper: link a single subdirectory from canonical → target.
# Usage: link_dir <subdir-name>
link_dir() {
    name="$1"
    src="${CANONICAL_DIR}/${name}"
    dst="${TARGET_HOME}/${name}"

    if [ ! -d "${src}" ]; then
        echo "skip   ${name}: source ${src} missing in canonical repo."
        return 0
    fi

    if [ -L "${dst}" ]; then
        existing=$(readlink "${dst}")
        if [ "${existing}" = "${src}" ]; then
            echo "ok     ${name}: symlink already points to canonical."
            return 0
        fi
        echo "error  ${name}: ${dst} is a symlink to ${existing} (expected ${src})." >&2
        echo "       remove it manually if you want to repoint to canonical." >&2
        return 1
    fi

    if [ -e "${dst}" ]; then
        echo "error  ${name}: ${dst} exists as a real path, not a symlink." >&2
        echo "       back up its contents and remove ${dst} before re-running bootstrap." >&2
        echo "       this script will not silently merge or overwrite real files." >&2
        return 1
    fi

    ln -s "${src}" "${dst}"
    echo "linked ${name}: ${dst} -> ${src}"
}

# Helper: copy (not symlink) a standards file from canonical/standards → target.
# Copy semantics so the user can edit ~/.cursor/<name>.md without the canonical
# source diverging silently. Re-running bootstrap refreshes the copy.
# Usage: copy_standard <filename>
copy_standard() {
    name="$1"
    src="${CANONICAL_DIR}/standards/${name}"
    dst="${TARGET_HOME}/${name}"

    if [ ! -f "${src}" ]; then
        echo "skip   standard ${name}: source ${src} missing."
        return 0
    fi

    if [ -L "${dst}" ]; then
        echo "error  standard ${name}: ${dst} is a symlink, expected a regular file." >&2
        echo "       remove the symlink and re-run bootstrap." >&2
        return 1
    fi

    cp -f "${src}" "${dst}"
    echo "copied standard ${name}: ${src} -> ${dst}"
}

# 3. Symlink portable directories. Order is independent.
link_dir "agents"
link_dir "skills"
link_dir "rules"
link_dir "hooks"

# 4. Copy standalone standards docs (copy, not symlink — see helper comment).
copy_standard "engineering-standards.md"
copy_standard "scalable-backend-design.md"

# 5. Refresh +x on every script under hooks/.
if [ -d "${TARGET_HOME}/hooks" ]; then
    find "${TARGET_HOME}/hooks/" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    echo "chmod  hooks/*.sh refreshed (+x)."
fi

echo
echo "bootstrap complete. ~/.cursor/ now points at ${CANONICAL_DIR}."
echo "to update later: cd ${CANONICAL_DIR} && git pull"
