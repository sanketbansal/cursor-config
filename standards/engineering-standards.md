# Engineering Standards

This is the canonical engineering-standards document. Every contributor — human or agent — reads this at the start of any substantive task and surfaces its pre-completion checklist into their todos.

## Ask, do not assume

You must never silently pick a default for an ambiguous parameter, never pre-answer your own clarifying question, and never proceed past an unconfirmed assumption on any decision touching credentials, irreversible operations, scope of work, public API shape, or destination of a write. Ask the user via `AskQuestion` (main agent) or a `cursor-checkpoint` block (subagent), then proceed. The full rule, with the narrow "small-and-stated assumption" exception and the list of banned phrasings, is at `~/.cursor/rules/ask-dont-assume.mdc` and applies in every mode.

## Non-negotiable rules

1. **Flat control flow.** No nested `if` / `else`. No nested `try` / `catch`. Use guard clauses and early returns. One `try` per logical unit, wrapping only the throwing call; map to a domain error and return or rethrow. Extract helpers when nesting would otherwise grow.
2. **Reuse before you write.** Search for an existing constant, enum, type, DTO, schema, helper, or DAO before creating a new one. If one exists, extend it.
3. **Canonical files for canonical concerns.** Constants live in `*.constants.*`, types and interfaces in `*.types.*` / `*.interfaces.*` / `dto/`, DAOs in `dao/`. No inline literals when a typed constant exists. Do not spawn a new `*.constants.*` / `*.types.*` / `dto/*` file per flow / use-case / fix; extend the canonical file for the module's concern.
4. **Strict typing.** No `any`. No `unknown`-as-pass-through. No `Record<string, unknown>` or `Record<string, string>` (or equivalents in other languages: Go `interface{}`, Dart `dynamic`, Python `Any`) where a real shape exists. Define the type / interface / schema and use it. Public functions always have explicit signatures.
5. **Generic code never depends on specific providers / services.** The dependency arrow goes specific → generic, never generic → specific. Use injection / strategy / registry for provider-specific behaviour.
6. **Respect module hierarchy.** A module owns its types and constants; do not reach across modules to grab fields. Re-export from the owner or move the symbol if shared. New logic belongs in the lowest module that owns the data it operates on.
7. **No legacy or backward-compatibility code unless the spec explicitly requests it.** No feature-flag dual paths, no deprecated wrappers, no fallbacks for old clients. When refactoring, remove the old path; do not leave it side-by-side.
8. **Tests are part of every change.** Update or add unit, integration, or regression tests with every behaviour change. Coverage of touched modules must not decrease. Run the relevant test suite and capture the result before claiming done. Unit test files MUST be named after the implementation file under test, not after the fix, ticket, or feature slug.
9. **Re-review against the plan before completion.** Walk the diff once focused only on adversarial cases (null, empty, malformed, concurrent, partial-failure). Update the plan if the implementation diverged.
10. **Zero code smell in touched code.** Remove duplication, dead code, magic numbers, oversized functions, long parameter lists, commented-out code, and stray logs in any file you modify. Run lint / format / type-check before declaring done.
11. **Lint and type errors take priority.** Fix them in any code you touched before writing more logic.
12. **Layered import direction (parent → child only).** Outer reusable layers (`src/types`, `src/dao`, `src/dto`, `src/constants`, `src/utils`) MUST NOT import from inner service / domain modules. Provider-specific code that needs domain types belongs in the inner module's `<domain>-providers/` sub-module, not in an outer-layer DAO directory.

## Production code only

Never ship stubs, dummy logic, or "we'll wire this up later" placeholders unless the spec explicitly asks for a scaffold. Never delete or work around critical existing logic to make a problem go away — diagnose the root cause and fix it.

## Pre-completion checklist (definition of done)

Every change must pass every item before the contributor says "done", commits, or opens a PR. Failing the checklist means the work is not done; fix it, do not narrate around it.

- Lint passes (`ruff check` / `eslint` / equivalent) on touched files.
- Format passes (`ruff format --check` / `prettier --check` / equivalent) on touched files.
- Type-check passes (`mypy` / `tsc --noEmit` / equivalent) on touched files.
- Relevant unit / integration / eval tests pass with output captured.
- Coverage of touched modules has not decreased.
- The diff is walked once focused on adversarial cases (null, empty, malformed, concurrent, partial-failure).
- Reuse search performed; no duplicate constants / types / helpers introduced.
- Layer-direction verified: outer reusable layers do not import from inner modules.
- No legacy / dual-path code introduced.
- All ambiguities surfaced via `AskQuestion` or `cursor-checkpoint`; no silent defaults picked.
