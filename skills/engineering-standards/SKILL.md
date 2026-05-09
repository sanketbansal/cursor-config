---
name: engineering-standards
description: Apply the canonical engineering standards (`~/.cursor/engineering-standards.md`) to any implementation, refactor, design, or review. Use at the start of every substantive task.
---

# Engineering standards

Read the canonical document at `~/.cursor/engineering-standards.md` before any substantive task and surface its pre-completion checklist into your todos.

## Non-negotiables (summary; canonical doc wins on conflicts)

1. Flat control flow — guard clauses, early returns, no nested `if` / `try`.
2. Reuse before write — search for existing constants / types / DTOs / DAOs / helpers first.
3. Canonical files for canonical concerns — `*.constants.*`, `*.types.*` / `*.interfaces.*` / `dto/`, `dao/`. Extend the existing file rather than spawning per-feature siblings.
4. Strict typing — no `any`, no `unknown`-as-pass-through, no untyped `Record` shapes; explicit signatures on public functions.
5. Generic code never depends on specific providers — dependency arrow goes specific → generic.
6. Respect module hierarchy — do not reach across modules for fields; re-export from the owner.
7. No legacy or backward-compatibility code unless the spec explicitly requests it.
8. Tests are part of every behaviour change — coverage of touched modules must not decrease.
9. Re-review the diff against the plan focused on adversarial cases before declaring done.
10. Zero code smell in touched code — no duplication, dead code, magic numbers, oversized functions, stray logs.
11. Lint and type errors take priority — fix in any code you touched before writing more logic.
12. Layered import direction — outer reusable layers (`src/types`, `src/dao`, `src/dto`, `src/constants`, `src/utils`) MUST NOT import from inner service / domain modules.

## Ask, do not assume

Surface every ambiguous decision via `AskQuestion` (main agent) or a `cursor-checkpoint` block (subagent) — see `~/.cursor/rules/ask-dont-assume.mdc` for the full rule. Never silently pick a default.

## Pre-completion checklist (definition of done)

- Lint, format, type-check pass on touched files.
- Relevant tests pass with output captured.
- Coverage of touched modules has not decreased.
- Diff walked once for adversarial cases (null, empty, malformed, concurrent, partial-failure).
- Reuse search done; no duplicate constants / types / helpers introduced.
- Layer-direction verified.
- No legacy / dual-path code introduced.
- All ambiguities surfaced via `AskQuestion` or `cursor-checkpoint`.

When the canonical doc and this summary disagree, the canonical doc wins. Pull it forward; do not edit this skill to match.
