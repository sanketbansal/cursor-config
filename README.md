# cursor-config

Canonical source of truth for custom Cursor agents, skills, rules, hooks, and standards docs. One clone per Mac at `/Users/Shared/cursor-config/`, copied into every macOS user's `~/.cursor/` via `bootstrap.sh`. Survives macOS-user switches and moves to a new machine without re-implementing any agent, skill, or rule.

## Layout

- `agents/` — custom subagents that ship into `~/.cursor/agents/`. Nine agent files (plus the `claude-code` runner) in two complementary groups:
  - **Pipeline subagents** that compose under `subagent-orchestration` (artefact dataflow `business-prompt → prd → architecture-doc → lld-plan → code-diff → deploy-artefact`, with verification on top):
    - `product-manager.md` — produces `prd` from a `business-prompt`.
    - `principal-engineer.md` — produces `architecture-doc` (and ADRs) from a `prd`.
    - `staff-engineer.md` — produces `lld-plan` (module decomposition, schema, sequenced waves) from `prd` + `architecture-doc`. Produces no code.
    - `software-engineer.md` — produces `code-diff` (production code + tests) from an `lld-plan`.
    - `dev-ops.md` — produces `deploy-artefact` (Dockerfiles, CI/CD workflows, IaC, package-manager scripts) from `lld-plan` + `code-diff`.
    - `qa-engineer.md` — produces `test-plan` + `qa-report` (layered test strategy, then executed verification with a routed defect log) from `prd` + `architecture-doc` + `lld-plan` + `code-diff`. Delegates unit-test authoring to `software-engineer` and routes each defect back to the responsible subagent.
  - **Specialist subagents** outside (or parallel to) the pipeline:
    - `ux-designer.md` — design-first UI/UX research + design specialist. Produces `ux-research` + `ux-design-spec` from a `prd`, and creates the actual design files (e.g. Figma) via MCP with every write relay-gated. Never writes frontend code (delegates to `software-engineer`); runs in parallel with `principal-engineer` after the PRD.
    - `ai-engineer.md` — design-first AI / multi-agent / LLM-system specialist. Produces `architecture-doc`, `lld-plan`, `distributed-design`, `eval-design`. Never writes code in deliverables unless agent mode explicitly asks.
    - `claude-code.md` + `claude-code.runner.sh` — thin relay that delegates implementation work to the locally installed Claude Code CLI (Anthropic) as a Cursor subagent, with an active-probe gate.
- `skills/` — custom user skills that ship into `~/.cursor/skills/`. Five skills:
  - `engineering-standards/` — auto-trigger on any code/design task; enforces the 17 standards (12 universal + 5 SOLID), OOP fundamentals, and the design-patterns catalogue from `standards/engineering-standards.md`.
  - `scalable-system-design/` — walks new backend / async / cache / migration / AI-system designs through the 7-step questionnaire and the 12 system-design primitives in `standards/scalable-backend-design.md`.
  - `subagent-orchestration/` — discovery-driven, dataflow-driven runbook for the parent Cursor agent. Builds the per-task dependency graph from each subagent's `produces`/`consumes` frontmatter and enforces the inviolable `cursor-checkpoint` relay rule (subagent question → `AskQuestion` → resume). Roster-agnostic; do not hard-code subagent names. §10 covers the plan-time orchestration deliverable; §11 is the artefact authoring & persistence lifecycle (see below).
  - `deployment-standards/` — universal-standards reference paired with the `dev-ops` subagent for Dockerfiles, CI/CD workflows, IaC, package-manager scripts, secrets, observability-at-deploy, and rollout / rollback safety.
  - `external-context-discovery/` — canonical runbook every subagent (and the parent) loads to discover whichever MCP servers are enabled on the runtime machine, match the task's information needs to capability classes inferred from each tool's `description`, call MCP safely (read-first, schema-first, ask before any write), and degrade gracefully when no MCP fits. Roster-agnostic; no hard-coded server names anywhere.
  - Cursor's built-in `~/.cursor/skills-cursor/` is NEVER mirrored here — that directory is Cursor-managed and has its own auto-sync.
- `rules/` — user-scoped rules that ship into `~/.cursor/rules/`. Two files:
  - `ask-dont-assume.mdc` — the universal "never silently pick a default; ask the user" policy that applies to every agent in every mode and to the orchestration relay.
  - `plan-orchestration.mdc` — plan-time orchestration policy. When the agent produces a plan for a non-trivial task, it must also compute and embed a subagent-orchestration workflow (dependency graph, dispatch waves, checkpoints, per-todo executor) from the available subagents, per the `subagent-orchestration` skill's §10. Trivial tasks skip it.
- `hooks/` — custom hook scripts that ship into `~/.cursor/hooks/`. Includes `relay-subagent-checkpoint.sh` — the `subagentStop` hook (Python) that scans subagent output for the `cursor-checkpoint` marker and injects a `followup_message` enforcing the `subagent-orchestration` relay rule. The `+x` bit is refreshed on every bootstrap run.
- `hooks.json` — top-level dotfile that registers `relay-subagent-checkpoint.sh` for the `subagentStop` event with `failClosed: false`. Copies to `~/.cursor/hooks.json`.
- `standards/` — standalone standards documents copied into `~/.cursor/`:
  - `engineering-standards.md` — canonical 17 standards + OOP fundamentals + design-patterns catalogue + pre-completion checklist. Every contributor (human or agent) reads this at the start of any substantive task.
  - `scalable-backend-design.md` — canonical 12 system-design primitives (idempotency, transactional outbox, idempotent consumers, circuit breakers, retries with backoff + jitter, bulkheads, backpressure, graceful shutdown, liveness vs readiness, caching, observability, forward-only migrations) + the 7-step design walkthrough + AI-specific extensions.
- `bootstrap.sh` — POSIX-shell idempotent copy-everything sync. Run once per user account.
- `launchagents/` — optional system-scope LaunchAgent that auto-runs `bootstrap.sh` at every user login on this Mac.
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

   That copies `agents/`, `skills/`, `rules/`, and `hooks/` into `~/.cursor/`, and copies `standards/engineering-standards.md`, `standards/scalable-backend-design.md`, and the top-level `hooks.json` into `~/.cursor/`. The script is idempotent and safe to re-run.

3. Verify:

   ```sh
   ls ~/.cursor/agents/             # 7 files: 5 pipeline + ai-engineer + claude-code (+ runner)
   ls ~/.cursor/skills/             # 4 skill folders
   ls ~/.cursor/hooks/              # relay-subagent-checkpoint.sh
   cat ~/.cursor/hooks.json         # subagentStop registration
   head ~/.cursor/engineering-standards.md
   ```

4. Compose your own User Rules text and paste it into **Cursor Settings → Rules → User Rules**. The recommended composition is short pointers to the canonical sources rather than copies of their content (see [Composing the User Rules](#composing-the-user-rules) below).

## Daily workflow

- Edit any file under `/Users/Shared/cursor-config/`.
- Re-run `bash /Users/Shared/cursor-config/bootstrap.sh` to push the change out to `~/.cursor/`. The optional auto-run-on-login LaunchAgent (see below) does this automatically at every login.
- Commit and push from `/Users/Shared/cursor-config/` like any other git repo.
- On a new Mac, run the first-time setup above. On a new macOS user account on an existing Mac, just run `bootstrap.sh`.
- When you change `standards/engineering-standards.md`, `standards/scalable-backend-design.md`, or `skills/subagent-orchestration/SKILL.md` and your User Rules pastes summary text from those, also re-paste your User Rules into Cursor Settings → Rules → User Rules — Cursor stores user rules in your account, not on disk, so a manual paste is required for the change to take effect.

### Why copy and not symlink

Earlier versions of `bootstrap.sh` symlinked `agents/`, `skills/`, `rules/`, and `hooks/` from canonical into `~/.cursor/`. Cursor reads these directories as real files in practice — every fresh install starts with `~/.cursor/agents/`, `~/.cursor/skills/`, and `~/.cursor/hooks/` as real directories, not symlinks. The symlink model also broke the moment a user already had any real file under those paths (the script bailed with "exists as a real path, not a symlink"). The current copy-everything model mirrors the layout Cursor is already reading from and is idempotent on top of any pre-existing real file. The trade-off — local edits under `~/.cursor/` no longer propagate back to canonical automatically — is intentional: edit in `/Users/Shared/cursor-config/` and run bootstrap to push out.

Note that `bootstrap.sh` overwrites destination files but does NOT delete files that exist in `~/.cursor/` but not in the canonical repo. If you remove a file from canonical, also delete the stale copy from `~/.cursor/` by hand on each user account.

#### Migrating from the symlink-era layout

Accounts bootstrapped before the copy-everything switch had `~/.cursor/{agents,skills,rules,hooks}` as symlinks into `/Users/Shared/cursor-config/`. On those accounts, `cp` aliases dst to src and BSD `cp` aborts with `identical (not copied)`. `bootstrap.sh` now detects and removes those legacy symlinks at the start of each `sync_tree` / `sync_file` call (printing a `migrate` line), so a single re-run of `bootstrap.sh` is sufficient — no manual `rm` needed. The check is a no-op for accounts that were never symlinked.

## Pipeline subagents

The five pipeline subagents (`product-manager`, `principal-engineer`, `staff-engineer`, `software-engineer`, `dev-ops`) compose end-to-end under the `subagent-orchestration` skill's dependency-graph procedure. Each agent declares `produces` / `consumes` against the artefact vocabulary in `skills/subagent-orchestration/SKILL.md` §3, and the parent Cursor agent builds a per-task graph from those declarations rather than from a fixed pipeline diagram. Different tasks produce different graphs; the user's task and what the user has already provided determine which agents fire.

Every subagent that pauses for input emits a fenced `cursor-checkpoint` block (schema in `skills/subagent-orchestration/SKILL.md` §1). The parent must relay the question to the user via `AskQuestion` verbatim, then resume the same subagent with `Task(resume=<id>, prompt=<answer>)`. This is the inviolable rule of the orchestration model — see `skills/subagent-orchestration/SKILL.md` §6 for the full protocol and `rules/ask-dont-assume.mdc` for the universal ask-don't-assume policy.

The two specialist subagents (`ai-engineer`, `claude-code`) sit alongside the pipeline. `ai-engineer` is design-first and produces markdown architecture / design / plan documents for AI / multi-agent / LLM systems; it switches to writing code only when the parent in agent mode explicitly asks. `claude-code` is a thin relay that delegates implementation work to the locally installed Claude Code CLI (Anthropic) — see [Claude Code subagent](#claude-code-subagent) below.

## Document artefact authoring and lifecycle

The six document-producing subagents (`product-manager`, `principal-engineer`, `staff-engineer`, `ai-engineer`, `dev-ops` Phase-1 plan, `qa-engineer` test-plan + qa-report) **persist their artefact to a file and author it incrementally** rather than emitting the whole document in chat. This is the fix for subagent resource-exhaustion during plan/document generation: a large document re-rendered in chat at every checkpoint is what trips the output/context limit. The canonical contract is `skills/subagent-orchestration/SKILL.md` §11; each agent carries a short "Artefact authoring & persistence" section that points to it.

Key guarantees:

- **Incremental, never re-emitted.** Each turn writes one section/wave to the file and returns only a short delta summary + the file path + (at a checkpoint) the `cursor-checkpoint` marker. On resume the file is edited in place, never re-printed.
- **Completeness contract (no partial handoff).** Each file carries a `status: in-progress | complete` header. An artefact is declared done — and the parent marks it satisfied — only when every required section is written and the agent's quality-bar self-check has passed against the full file. A checkpoint pause is never a completion, and a downstream agent never consumes an `in-progress` artefact (it raises a blocking question instead of inferring the missing detail). Proportional depth right-sizes scope, never the quality-bar floor — so completeness and detail are never traded for shorter output.
- **Transient vs deliverable + cleanup.** Intermediate artefacts (consumed only by downstream subagents) are written to a per-task ephemeral temp working dir outside the repo; the parent auto-deletes that dir when orchestration completes successfully. Deliverables the user asked to keep are written into the repo and preserved. The auto-delete is a pre-authorized policy strictly scoped to the task's own temp dir (the one carve-out to the destructive-delete clause of `rules/ask-dont-assume.mdc`).

## Hooks

`hooks.json` registers a `subagentStop` hook (`hooks/relay-subagent-checkpoint.sh`) with `failClosed: false`. Every time a subagent terminates, the hook scans its output for a fenced `cursor-checkpoint` block. If one is present, it parses the embedded YAML and injects a `followup_message` instructing the parent to call `AskQuestion` verbatim with the subagent's question and options, then resume the subagent with the user's answer.

The hook is defence-in-depth — the User Rules and the `subagent-orchestration` skill require the parent to relay regardless of hook state. `failClosed: false` means a hook bug never wedges the agent.

The hook script is roster-agnostic: there is no per-subagent name list anywhere in it. The presence of the `cursor-checkpoint` block is the sole trigger. Any subagent (current or future) that emits the marker gets relayed; any subagent (or Cursor built-in like `explore`, `shell`, `browser-use`) that does not emit it makes the script a no-op.

## Composing the User Rules

Cursor User Rules apply to **Agent (Chat) only**, not to Inline Edit (Cmd/Ctrl+K). Rule precedence is **Team → Project → User**. Workspace-level rules in `<repo>/.cursor/rules/*.mdc` win on conflicts within a project.

Cursor stores User Rules in your account, not on disk — there is no file in this repo that is auto-applied as User Rules. You compose the text yourself once per Cursor account and paste it into **Cursor Settings → Rules → User Rules**. The repo deliberately does not ship a paste-source file because most of the standards content already lives in canonical files under `standards/` and `skills/`, and duplicating it into a User Rules paste-source violates DRY (and silently drifts).

Recommended composition — short pointers to the canonical sources instead of copies of their content:

```text
# Engineering standards (always apply)
Follow the canonical engineering standards in `~/.cursor/engineering-standards.md` and the `engineering-standards` skill at `~/.cursor/skills/engineering-standards/SKILL.md` for every implementation, bug fix, refactor, design, plan, and code review. Read the canonical document at the start of any substantive task and surface its pre-completion checklist into your todos.

# Scalable backend design (apply to backend services)
Follow `~/.cursor/scalable-backend-design.md` and the `scalable-system-design` skill at `~/.cursor/skills/scalable-system-design/SKILL.md` whenever designing a new service, integration, async pipeline, caching layer, or migration. Walk the 7-step questionnaire and apply the 12 system-design primitives before producing the design.

# Subagent orchestration (always apply)
For any non-trivial coding, design, deployment, audit, or review task, follow the orchestration runbook in `~/.cursor/skills/subagent-orchestration/SKILL.md`. Discover registered subagents under `~/.cursor/agents/`, build the per-task dependency graph from each agent's `produces`/`consumes` frontmatter, and dispatch by graph topology. When any subagent emits a fenced `cursor-checkpoint` block, your first action is to relay the question to the user via `AskQuestion` verbatim and resume the subagent with the answer; never invent answers, never paraphrase.

# Plan-time orchestration (always apply)
Follow `~/.cursor/rules/plan-orchestration.mdc`. When you produce a plan for a non-trivial task, also embed an Orchestration workflow computed from the available subagents per the `subagent-orchestration` skill's §10 — the dependency graph, dispatch waves (parallel vs sequential), checkpoint map, and a responsible executor on every todo. This is an on-disk rule that auto-applies; this pointer is reinforcement. Trivial tasks skip it.

# Ask, do not assume (always apply)
Follow `~/.cursor/rules/ask-dont-assume.mdc` — never silently pick a default, never pre-answer your own clarifying question, never proceed past an unconfirmed assumption on credentials, irreversible operations, scope of work, public API shape, or destination of a write.
```

Add your own operational preferences (operating environment, communication style, scope discipline, etc.) below the pointers as needed; those are agent-behaviour preferences and don't belong in the canonical standards files.

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
- `CLAUDE_CODE_RUNNER_ADD_DIRS` — colon-separated absolute paths granted to Claude as `--add-dir` (default: auto-detect from a sibling `*.code-workspace` file's `folders` array, falling back to cwd-only).

### Multi-root workspace support

Cursor multi-root workspaces (where a single window has more than one root folder) are first-class. Each `--add-dir` Claude receives is a separate sandbox-allowed root.

The runner resolves the `--add-dir` set in this precedence order:

1. **`CLAUDE_CODE_RUNNER_ADD_DIRS` env var, when set.** Colon-separated absolute paths. Always wins. Use this when you want explicit control or when auto-detect cannot find your workspace file.

   ```sh
   export CLAUDE_CODE_RUNNER_ADD_DIRS="/Users/me/repo-a:/Users/me/repo-b"
   ```

2. **Auto-detect from `*.code-workspace` files.** The runner scans `$HOME/*.code-workspace` and `$(dirname "$PWD")/*.code-workspace`. If any of those files has a `folders` array containing the basename of the current working directory, the runner uses every folder in that array. This covers the common case where you opened the workspace from a saved `.code-workspace` file.

3. **Fallback: cwd-only.** Same behavior as before this support existed.

The resolved set always includes the current working directory (deduplicated). Non-existent paths are silently dropped — Claude only ever receives `--add-dir` for directories that exist.

Limitations: ad-hoc multi-root workspaces (folders added via "Add Folder to Workspace…" without saving a `.code-workspace` file) cannot be auto-detected because Cursor stores their state in `~/Library/Application Support/Cursor/User/workspaceStorage/<id>/state.vscdb` rather than a parseable JSON file. For those, set `CLAUDE_CODE_RUNNER_ADD_DIRS` explicitly.

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
3. Re-run `bash /Users/Shared/cursor-config/bootstrap.sh` (or wait for the next login auto-run) to push the new file out to `~/.cursor/agents/`.

## Adding a new rule

1. Drop a new `<name>.mdc` into `rules/`. Frontmatter sets `description`, `globs` (e.g. `"**"` for all files), and `alwaysApply` (boolean).
2. Body in markdown.
3. Re-run `bootstrap.sh` to push the new file out.

## Adding a new skill

1. Create a `skills/<name>/SKILL.md`. Frontmatter sets `name` and `description`; body explains when to use the skill and the procedure to follow.
2. Re-run `bootstrap.sh` to push the new file out.

## What is NOT here (deliberately)

- `~/.cursor/skills-cursor/` — Cursor's built-in skills, auto-synced by Cursor itself. Touching them would break Cursor's sync.
- `~/.cursor/projects/`, `~/.cursor/plans/`, `~/.cursor/plugins/cache/`, `~/.cursor/extensions/` — runtime state, per-machine. Stays per-user.
- Cursor application settings (`~/Library/Application Support/Cursor/User/settings.json`) — covered by Cursor's own Settings Sync when you sign in.
- Secrets, credentials, OpenAI / Anthropic API keys. Keep those in your shell profile or a secrets manager.

## Cross-machine path

Same as first-time setup. `git clone` this repo to `/Users/Shared/cursor-config/` on the new machine; each user runs `bootstrap.sh`. Updates flow via `git pull` followed by another `bootstrap.sh` run on each macOS user account (or via the auto-run-on-login LaunchAgent).

## Optional: iCloud-backed mirror

If you want zero-touch single-user multi-Mac sync without a git remote, `rsync` `/Users/Shared/cursor-config/` into `~/Library/Mobile Documents/com~apple~CloudDocs/cursor-config/` from a launchd job. Note that iCloud only syncs to the iCloud-signed-in user, so this does not help cross-USER on the same Mac. The git + `/Users/Shared/` path remains the primary; iCloud is a backup mirror at most.
