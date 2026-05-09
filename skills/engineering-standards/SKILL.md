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

## Design vocabulary (summary)

The canonical doc (`~/.cursor/engineering-standards.md`) names the design principles every change is reviewed against. One bullet per family; the doc is the source of truth and wins on conflicts.

- **Object-oriented design pillars** — encapsulation (hide implementation, guard invariants), abstraction (depend on contracts not concretes), inheritance sparingly (true *is-a* with Liskov; otherwise compose), polymorphism (dispatch via interface, not `if`-on-type).
- **SOLID** — SRP (one reason to change), OCP (extend by adding strategies, do not edit working code), LSP (subtypes substitutable, no `NotImplementedError` overrides), ISP (small focused interfaces over wide ones), DIP (high-level and low-level both depend on a shared abstraction; reinforces rules 5 and 12).
- **Universal design principles** — DRY, KISS, YAGNI, Law of Demeter (no `a.b.c.d.do()` chains), Composition-over-Inheritance, Tell-Don't-Ask, Principle of Least Astonishment, Fail-Fast, Make-Illegal-States-Unrepresentable.
- **Clean-code basics** — intention-revealing names (no `tmp` / `data` / `helper` placeholders), function size ≤ 30 lines target / ≤ 50 lines hard cap, 0–3 parameters (4+ groups into a typed DTO), comments explain *why* not *what*, domain error types (never `str(e)` in user paths), separate pure computation from effect.
- **Cohesion and coupling** — high cohesion (a module's symbols change together), low coupling (small stable public surface), separation of concerns (UI / orchestration / domain / persistence / external IO in distinct layers). Rule 12 (layered import direction) is the structural enforcement of low coupling.

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
