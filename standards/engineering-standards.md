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

## Object-oriented design pillars

The four pillars are how this codebase organises behaviour. They apply in every language we use — Python `class` and `Protocol`, TypeScript `class` and `interface`, Go `struct` and `interface`, Rust `struct` and `trait`.

- **Encapsulation.** Hide implementation; expose behaviour. State is private by default, mutated only through methods that guard the invariant. No public mutable fields when an invariant exists. Modules / packages keep their internals unexported.
- **Abstraction.** Consumers depend on the contract (interface, protocol, trait), not the concrete class. The public surface is the contract; everything else is an implementation detail and free to change.
- **Inheritance — sparingly.** Inherit only when there is a true *is-a* relationship and Liskov substitution holds. Default to composition. Inheritance for code reuse is an anti-pattern; use a collaborator field instead.
- **Polymorphism.** Replace `if`-on-type and `switch`-on-tag with dispatch through an interface or a strategy registry. Substitutable subtypes mean the call site does not have to know which concrete type ran.

## SOLID

The five named principles — they are the design vocabulary for the rest of this document.

- **S — Single Responsibility Principle.** A class or module has one reason to change. If two stakeholders pull it in different directions (auth team and pricing team both edit the same class), split it. The smell is a class whose name needs an "and" or a "Manager" / "Handler" / "Util" suffix.
- **O — Open / Closed Principle.** Open for extension, closed for modification. Add new behaviour by adding a new strategy / handler / registration; do not edit working code. Reinforces rule 5 — provider-specific behaviour goes through injection or a registry, never an `if provider == "..."` ladder.
- **L — Liskov Substitution Principle.** Subtypes are substitutable for their base type without changing correctness. No `NotImplementedError` overrides. No subtype that strengthens preconditions or weakens postconditions. If a subtype cannot honour the contract, it is not a subtype — it is a sibling.
- **I — Interface Segregation Principle.** Many small focused interfaces beat one wide one. Clients depend only on the methods they call. The smell is an interface where most consumers stub out half the methods.
- **D — Dependency Inversion Principle.** High-level modules and low-level modules both depend on a shared abstraction; neither imports the other directly. Reinforces rules 5 and 12 — the dependency arrow goes specific → generic, never the other way, and outer reusable layers do not import inner domain modules.

## Universal design principles

The cross-cutting principles that keep code simple and easy to read.

- **DRY (Don't Repeat Yourself).** Every piece of knowledge has one canonical representation. Reinforces rule 2 — search for an existing constant / type / helper first; extend it rather than duplicate it.
- **KISS (Keep It Simple, Stupid).** Pick the simplest design that solves the problem. Complexity is a debt; pay it only when forced to. The simplest design that passes the tests wins; cleverness is not a virtue.
- **YAGNI (You Ain't Gonna Need It).** Do not add capability for hypothetical future needs. No speculative configuration knobs, no "in case we want to swap this out later" interfaces with one implementation, no dead code "we might need." Delete dead code immediately.
- **Law of Demeter.** A method talks only to its own fields, its parameters, and objects it creates. No `a.b.c.d.do_thing()` train-wreck chains — those couple the caller to the entire object graph and break when any link in the chain changes.
- **Composition over inheritance.** Assemble behaviour from collaborators (delegation) instead of inheriting from a base class. Composition is more flexible, easier to test, and avoids the fragile-base-class problem.
- **Tell-Don't-Ask.** Call methods that do work; do not pull data out of an object and act on it externally. Behaviour belongs with the data it operates on.
- **Principle of Least Astonishment.** Code behaves the way a reader would predict from its name and context. A function called `get_user` does not also send an email. Side effects live in functions whose names admit they have side effects.
- **Fail-Fast.** Validate inputs at the boundary; raise on invariant violation. Do not silently fall back to a default value when an invariant breaks — silent fallbacks hide bugs and accumulate as drift.
- **Make-Illegal-States-Unrepresentable.** Types and constructors disallow invalid combinations. If two fields cannot legally be set together, model them as a sum type or two distinct types — do not push the check to runtime.

## Clean-code basics

The microscopic readability rules. Workspace rules with stricter limits (such as a project's `AGENTS.md` per-type function-size table) override these defaults on project-specific concerns.

- **Intention-revealing names.** Functions name the effect they have; variables name the value they hold. Avoid `data` / `info` / `tmp` / `helper` / `process` / `do_stuff` unless the scope is genuinely that generic. No type-encoding prefixes (no `strName`, `iCount`, `m_field`). A reader should not need a comment to understand the name.
- **Function size.** Target ≤ 30 lines, hard cap ≤ 50 lines. The only exception is a pure dispatch table (a flat `match` / `switch` / lookup that adds no logic). Larger functions get split by extracting helpers — each helper is a named concept.
- **Parameter count.** 0–3 parameters is ideal. 4+ parameters means the parameters belong together; group them into a typed parameter object (DTO) per rule 3. Boolean flag parameters that change behaviour are usually a sign the function should be two functions.
- **Comments.** Comments explain *why* and the trade-off — never *what* the code obviously does. Delete commented-out code; the version-control history is the archive. Prefer a clearer name over a clarifying comment.
- **Error handling is first-class.** Domain errors are explicit types, exception classes, or enums — never `str(e)` in user-facing paths. Map low-level exceptions to domain errors at the boundary. One `try` per logical unit per rule 1.
- **Pure where possible.** Separate computation (pure, no I/O, no global state) from effect (I/O, mutation, time). Pure functions are trivially testable; effectful functions get tested with fakes / mocks at the seam.

## Cohesion and coupling

The structural-quality vocabulary that explains *why* the rules above produce maintainable code.

- **High cohesion.** A module's symbols change together. If half the module's functions touch one struct and the other half touch a different one, split the module. Cohesion is the SRP applied at module scope.
- **Low coupling.** A module's public surface is small and stable. Consumers depend on the surface, not on internals. Low coupling makes a module replaceable without ripple effects.
- **Separation of concerns.** Distinct concerns live in distinct layers — UI, orchestration, domain, persistence, external IO. One symbol does not mix two concerns. Mixing concerns is the most common source of "I changed the colour and three tests broke" surprise.
- **Layered import direction (rule 12) is the structural enforcement of low coupling.** Outer reusable layers do not import inner domain modules. Provider-specific code lives next to the inner module that owns the data. Cohesion and coupling get measured at code review by walking the import graph; if outer reaches inner, coupling has leaked.

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
- No SOLID violation introduced — no God class / God function (SRP), no wide / fat interface forcing clients to depend on methods they do not call (ISP), no concrete-class dependency wired in a constructor instead of injected as an abstraction (DIP), no inheritance for code reuse where composition would do.
- Function-size and parameter-count limits respected on touched code (≤ 30 lines target, ≤ 50 lines hard cap; 0–3 parameters or grouped into a typed parameter object per rule 3). Workspace-rule limits, when stricter, win.
- Public surface uses intention-revealing names; no `tmp` / `data` / `info` / `helper` / `process` / `do_stuff` placeholders left in the diff; no type-encoding prefixes.
