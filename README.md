# cursor-config

Canonical source of truth for custom Cursor agents, skills, rules, hooks, and standards docs. One clone per Mac at `/Users/Shared/cursor-config/`, symlinked into every macOS user's `~/.cursor/` via `bootstrap.sh`. Survives macOS-user switches and moves to a new machine without re-implementing any agent, skill, or rule.

## Layout

- `agents/` — custom subagents that ship into `~/.cursor/agents/`. Includes `ai-engineer.md`.
- `skills/` — custom user skills that ship into `~/.cursor/skills/`. Includes `subagent-orchestration`, `engineering-standards`, `scalable-system-design`. Cursor's built-in `~/.cursor/skills-cursor/` is NEVER mirrored here — that directory is Cursor-managed and has its own auto-sync.
- `rules/` — user-scoped rules that ship into `~/.cursor/rules/`. Includes `ask-dont-assume.mdc`.
- `hooks/` — custom hook scripts that ship into `~/.cursor/hooks/`. The `+x` bit is refreshed on every bootstrap run.
- `standards/` — standalone standards documents copied (not symlinked) into `~/.cursor/`. Includes `engineering-standards.md` and `scalable-backend-design.md`.
- `bootstrap.sh` — POSIX-shell idempotent bootstrapper. Run once per user account.
- `README.md` — this file.

## First-time setup on a new Mac

1. Clone (or copy) this repo to `/Users/Shared/cursor-config/`. `/Users/Shared/` is the macOS-standard sticky-bit world-writable directory, so every user account on the Mac can read it.

   ```sh
   git clone <remote-url> /Users/Shared/cursor-config
   ```

   If you have no remote yet, the repo can also live there as a local-only git working tree.

2. Each user runs `bootstrap.sh` from their own account:

   ```sh
   /Users/Shared/cursor-config/bootstrap.sh
   ```

   That populates `~/.cursor/agents`, `~/.cursor/skills`, `~/.cursor/rules`, `~/.cursor/hooks` as symlinks into the canonical clone, and copies `engineering-standards.md` and `scalable-backend-design.md` into `~/.cursor/`. The script is idempotent and safe to re-run.

3. Verify:

   ```sh
   ls -lL ~/.cursor/agents/ai-engineer.md
   ls -lL ~/.cursor/rules/ask-dont-assume.mdc
   cat ~/.cursor/engineering-standards.md | head
   ```

## Daily workflow

- Edit any file under `/Users/Shared/cursor-config/`. Symlinks make every user see the change immediately. Standards-doc edits propagate via the next `bootstrap.sh` run (copy semantics).
- When `standards/engineering-standards.md` or `standards/scalable-backend-design.md` is edited, each macOS user runs `bash /Users/Shared/cursor-config/bootstrap.sh` once to refresh the copy in `~/.cursor/`. The agent and skill changes need no re-run because they live behind symlinks.
- Commit and push from `/Users/Shared/cursor-config/` like any other git repo.
- On a new Mac, run the first-time setup above. On a new macOS user account on an existing Mac, just run `bootstrap.sh`.

## Adding a new subagent

1. Drop a new `<name>.md` into `agents/`. The file's YAML frontmatter must include `name`, `description`, and (per `skills/subagent-orchestration/SKILL.md`) `produces` and `consumes` artefact-type lists. The body is the system prompt.
2. The boilerplate ask-don't-assume paragraph must appear verbatim in the prompt body (canonical wording in `skills/subagent-orchestration/SKILL.md`). Every custom subagent uses the same wording so the policy stays uniform.
3. No bootstrap re-run is needed; symlinks pick up the new file the next time Cursor walks `~/.cursor/agents/`.

## Adding a new rule

1. Drop a new `<name>.mdc` into `rules/`. Frontmatter sets `description`, `globs` (e.g. `"**"` for all files), and `alwaysApply` (boolean).
2. Body in markdown.
3. No bootstrap re-run is needed.

## Adding a new skill

1. Create a `skills/<name>/SKILL.md`. Frontmatter sets `name` and `description`; body explains when to use the skill and the procedure to follow.
2. No bootstrap re-run is needed.

## What is NOT here (deliberately)

- `~/.cursor/skills-cursor/` — Cursor's built-in skills, auto-synced by Cursor itself. Touching them would break Cursor's sync.
- `~/.cursor/projects/`, `~/.cursor/plans/`, `~/.cursor/plugins/cache/`, `~/.cursor/extensions/` — runtime state, per-machine. Stays per-user.
- Cursor application settings (`~/Library/Application Support/Cursor/User/settings.json`) — covered by Cursor's own Settings Sync when you sign in.
- Secrets, credentials, OpenAI / Anthropic API keys. Keep those in your shell profile or a secrets manager.

## Cross-machine path

Same as first-time setup. `git clone` this repo to `/Users/Shared/cursor-config/` on the new machine; each user runs `bootstrap.sh`. Updates flow via `git pull` in the shared clone.

## Optional: iCloud-backed mirror

If you want zero-touch single-user multi-Mac sync without a git remote, `rsync` `/Users/Shared/cursor-config/` into `~/Library/Mobile Documents/com~apple~CloudDocs/cursor-config/` from a launchd job. Note that iCloud only syncs to the iCloud-signed-in user, so this does not help cross-USER on the same Mac. The git + `/Users/Shared/` path remains the primary; iCloud is a backup mirror at most.
