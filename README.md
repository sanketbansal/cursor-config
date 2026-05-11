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

## Optional: auto-run at every user login (recommended for shared Macs)

Once enabled, every macOS user on this Mac (current and future, GUI logins) auto-runs `bootstrap.sh` at login. No per-user setup. The mechanism is a system-scope LaunchAgent at `/Library/LaunchAgents/com.cursor-config.bootstrap.plist`, which macOS loads automatically into every user session.

### Enable

Either accept the prompt the next time you run `bootstrap.sh` from a terminal, or run the installer directly. Both paths self-elevate to `sudo`; you only type your password once.

```sh
sudo bash /Users/Shared/cursor-config/launchagents/install-autorun.sh
```

### Disable

```sh
sudo bash /Users/Shared/cursor-config/launchagents/uninstall-autorun.sh
```

The uninstaller removes the LaunchAgent. Per-user log files at `~/Library/Logs/cursor-config-bootstrap.log` are intentionally left in place so you can inspect them; delete them manually if you want.

### Logs

Each user gets `~/Library/Logs/cursor-config-bootstrap.log` after the LaunchAgent fires the first time. The file is truncated and rewritten on each login (idempotent bootstrap output).

### "Background Items" notification

On macOS Sequoia (15) and later, the OS shows a one-time notification when the LaunchAgent first loads, and lists it in `System Settings → General → Login Items` under "Background Items". This is macOS being transparent — leave the toggle on for the auto-run to keep working.

### When auto-run does NOT cover you

- Users who never log in via the GUI (SSH-only). They can run `bootstrap.sh` manually as needed.
- A new Mac with no canonical repo at `/Users/Shared/cursor-config/` — bootstrap will exit with `error: canonical dir ... does not exist` and login proceeds normally. Clone the repo into place and the next login auto-bootstraps.

## Claude Code subagent

The `claude-code` subagent at `agents/claude-code.md` delegates coding work to the locally installed [Claude Code](https://claude.ai) CLI (Anthropic) as a Cursor subagent — a peer to `ai-engineer.md`. The main Cursor agent invokes it the same way it invokes any custom subagent ("Use the `claude-code` subagent to refactor `src/foo.py` so ..."). All actual `claude` CLI calls happen through the helper runner at `agents/claude-code.runner.sh`; the subagent's `.md` file is just the system prompt that tells the LLM how to drive the runner. You do not run the runner by hand for normal use.

### Prerequisites

1. The `claude` CLI v2.x must be installed on the user's machine:

   ```sh
   curl -fsSL https://claude.ai/install.sh | bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
   ```

2. The user must be signed in via `claude auth login`. The runner reports `not_logged_in` until this is done.

### Pre-flight gate (active probe)

Before every delegation, the subagent calls `claude-code.runner.sh probe`. That runs `claude auth status --json` (free, ~100 ms) and, if authenticated, sends a 1-token round-trip on the same model the real call will use. Per-model rate limits exist on the team plan, so probing the actual target model is the only honest signal.

Observed probe cost on this workstation (Opus, team-plan auth): ~$0.06 on the very first probe after `~/.claude/` cache is cold (cache-fill of ~8 K tokens of system prompt charged at full Opus rate), then dropping to ~$0.001 – $0.005 per subsequent probe while the 1-hour ephemeral cache stays warm. On team-plan auth this is quota slices, not dollars, but it is real quota — about 0.1 % of a 5-hour Opus quota per probe in the worst case. If that bothers you, switch the gate strategy as described under "Cost note" below.

If the probe reports `available: false`, the subagent returns the envelope to the parent and stops. The parent decides whether to retry, fall back to another subagent, or escalate. The subagent never retries on its own.

### Output contract (envelope)

Every subagent reply starts with one line of JSON on its own line:

```
{"available":true,"reason":null,"auth":{...},"result":...,"result_format":"json","files_modified":["src/foo.ts"],"elapsed_ms":12345,"cli_version":"2.1.138","exit_code":0,"stderr_tail":null}
```

`reason` is `null` on success or one of: `not_installed`, `not_logged_in`, `rate_limit`, `budget_exceeded`, `auth_error`, `timeout`, `unknown_error`. See `agents/claude-code.md` section 2.6 for what each one means.

### Environment overrides

The runner reads these to customise a call without editing the script. Set them in the calling shell (or in `~/.cursorrc`-style profiles) before invoking the subagent. Defaults in parentheses.

- `CLAUDE_CODE_RUNNER_MODEL` — target model (default: `~/.claude/settings.json` → `model`).
- `CLAUDE_CODE_RUNNER_BUDGET` — `--max-budget-usd` cap (default: `1.0`; only enforced on metered-API auth).
- `CLAUDE_CODE_RUNNER_EFFORT` — `--effort` level: `low|medium|high|xhigh|max` (default: `high`).
- `CLAUDE_CODE_RUNNER_PERM` — `--permission-mode`: `plan|acceptEdits|bypassPermissions|auto|default|dontAsk` (default: `acceptEdits`).
- `CLAUDE_CODE_RUNNER_TIMEOUT` — wall-clock seconds per call (default: `600`).
- `CLAUDE_CODE_RUNNER_CWD` — cwd Claude Code runs in (default: caller's `$PWD`).

### Running the runner directly (debugging only)

```sh
# Free auth-only preflight
bash /Users/Shared/cursor-config/agents/claude-code.runner.sh preflight

# Active probe (1-token round-trip)
bash /Users/Shared/cursor-config/agents/claude-code.runner.sh probe

# Run a brief from a prompt file
echo "Print the three most recently modified files in this repo, one per line. Do not modify anything." > /tmp/brief.txt
bash /Users/Shared/cursor-config/agents/claude-code.runner.sh run /tmp/brief.txt
```

All three subcommands print exactly one line of JSON on stdout and route diagnostics to stderr.

### Troubleshooting

- `reason: not_installed` — install via the curl-pipe above and put `~/.local/bin` on `PATH`. Cursor's Shell tool doesn't inherit your interactive `PATH`; the runner bootstraps `PATH` itself, so this almost always means the CLI is genuinely missing.
- `reason: not_logged_in` — `claude auth login` in a terminal. The runner uses your existing auth state under `~/.claude/`.
- `reason: rate_limit` — wait, switch to a different model via `CLAUDE_CODE_RUNNER_MODEL=sonnet` (lower limits than opus on most plans), or hand the task to a different subagent.
- `reason: timeout` — raise `CLAUDE_CODE_RUNNER_TIMEOUT=1800` for one call, or simplify the brief. Default 600 s is intentionally generous-but-bounded so a hung call cannot block the Cursor agent forever.
- `reason: unknown_error` — read `stderr_tail` in the envelope. If you see a new rate-limit message the regex doesn't catch, extend `_classify_failure` in `agents/claude-code.runner.sh`.

### Cost note

Probes cost what is shown under "Pre-flight gate" above — a few cents per cold probe, near-zero per warm one, real quota on team plans. If that bothers you, switch the subagent's gate strategy to "opportunistic" by editing `agents/claude-code.md` section 2.2 to skip the probe and rely on real-call error classification — but at the cost of one wasted full call per rate-limit episode.

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
