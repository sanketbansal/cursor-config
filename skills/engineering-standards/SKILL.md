---
name: engineering-standards
description: Use whenever implementing a feature, fixing a bug, refactoring, designing a new module or architecture, reviewing code, or writing/updating a plan. Enforces the universal engineering standards — the 17 standards (12 universal + 5 SOLID), the OOP fundamentals (encapsulation, abstraction, polymorphism not type checks, composition over inheritance, tell-don't-ask, Law of Demeter, single level of abstraction), and the design-patterns catalogue (Strategy, Factory, Registry, Repository, Adapter, Decorator, Observer, Builder, Template Method, Chain of Responsibility, Specification, Result/Either). Always load before producing code or design output.
---

# Engineering Standards

This skill enforces the universal engineering standards defined in the canonical document:

> [`~/.cursor/engineering-standards.md`](~/.cursor/engineering-standards.md)

**Always read the canonical document at the start of any substantive task** (implementation, bug fix, refactor, design, plan, code review). The canonical doc is the source of truth — if anything below conflicts with it, the canonical doc wins.

## When to use this skill

Trigger on any of:

- Writing new code, fixing a bug, or refactoring existing code.
- Designing a new module, service, integration, or architecture.
- Producing or updating an implementation plan or spec.
- Reviewing a diff, PR, or your own work before claiming completion.

For backend system design specifically, also load the companion skill [`scalable-system-design`](../scalable-system-design/SKILL.md), which walks new designs through the 7-step questionnaire (workload → state → failure → idempotency → events → observability → safe-failure).

## What to do

### 1. Load the standards

Read the canonical document and surface the **seventeen** standards (twelve universal + five SOLID), the OOP fundamentals subsection, the design-patterns catalogue, and the pre-completion checklist into your working context.

The standards in summary:

1. Flat control flow (no nested `if`/`else` or `try`/`catch`).
2. Code is read more than written.
3. Reuse before write.
4. Canonical files (one `*.constants.*`, one `*.types.*`, one `dto/`; one `*.unit.test.ts` per source file).
5. Zero code smell in touched code.
6. Re-review every implementation against the plan.
7. No legacy / back-compat code unless explicitly requested.
8. Tests are part of the change.
9. Generic flows must not depend on specific providers/services.
10. Module hierarchy / nuclear logic.
11. Strict typing (no `any`, no loose `Record<...>`).
12. Layered import direction (outer layers do not import from inner service modules).
13. SRP — single reason to change per class / module / function.
14. OCP — new variants extend via strategy registration, not by editing a `switch` chain.
15. LSP — every implementation honours the preconditions, postconditions, and invariants of its interface.
16. ISP — small, role-specific interfaces over god interfaces.
17. DIP — high-level modules depend on interfaces; concrete classes are wired at the composition root.

OOP fundamentals (load alongside the SOLID standards): encapsulation, abstraction, polymorphism (not `instanceof` / `switch (type)`), composition over inheritance, tell-don't-ask, Law of Demeter, single level of abstraction within a function.

Also load the **Minimal footprint and solution-shape-first** discipline (canonical section of the same name):

- **Solution-shape first.** Before writing or planning, weigh 2-3 candidate approaches on reuse, new surface (files / lines), and blast radius, and take the leanest correct one. Do not start coding the first (usually most additive) idea.
- **Minimal footprint.** Default to zero new files; justify every new file / class / function against extending something that already exists. Prefer adding a method or branch to an existing unit over a near-duplicate new one.
- **Not code golf.** Fewer lines come from reuse, composition, and polymorphism — never from sacrificing flat control flow, strict typing, SRP, tests, or readability. KISS forbids both over- and under-engineering.

### 2. Apply during design and planning

- In any plan/spec, add a **Non-Functional Requirements** section that explicitly addresses:
  - Flat control flow expectations.
  - Reuse of existing constants/types/DTOs/DAOs (list the specific symbols you plan to reuse).
  - Strict typing — name the interfaces/schemas you will define or extend.
  - Generic ↔ provider boundary (which module owns what; what direction imports flow).
  - Whether any back-compat is required (default: no).
  - Test plan and coverage commands.
- Module placement: choose the **lowest** module that owns the data you operate on. Do not pull fields from sibling modules; re-export from the owner or move the symbol.

### 3. Apply during implementation

- Before adding a new constant/type/DTO/DAO/util, search for an existing one and extend it if possible.
- Keep functions to one level of conditional nesting; extract helpers otherwise.
- One `try` per logical unit, wrapping only the operation that can throw. Map to a domain error and return or rethrow.
- No `any`, no `Record<string, unknown>` (and friends) where a real shape exists. Define the type and use it.
- Do not import from a specific provider/service module inside generic code — generic code is consumed by specific code, never the reverse.
- Outer reusable layers (`src/types`, `src/dao`, `src/dto`, `src/constants`, `src/utils`, or the equivalents in your project) **MUST NOT** import from inner service / domain modules. Provider-specific code that needs domain types belongs inside the inner module's `<domain>-providers/` sub-module, not in an outer-layer DAO directory. Run `rg "from '\.\./\.\./<inner-module>/" src/types src/dao src/dto src/constants src/utils` for every inner module touched before claiming done; any new entry beyond the project's known-debt list is a layering violation.
- Do not add legacy/back-compat shims, dual code paths, dead code, commented-out code, or stray logs.
- Watch for the SOLID-touched anti-patterns and refuse them in your own diff:
  - **`switch (type)` / `if (provider === 'X')` in business logic** — register the variant in a registry; the dispatcher iterates over the registry. (Standard 14 / OCP.)
  - **`instanceof` / `switch (kind)` in business logic** — use polymorphism. Either the type system is wrong or the polymorphism is missing. (OOP fundamentals.)
  - **Inheritance chain** (apart from framework-mandated bases like `Error`, `EventEmitter`, an ORM `Model`) — use composition. (OOP fundamentals.)
  - **God interface** (one `Repository` with thirty methods consumed by every reader and writer) — split into role-specific ports. (Standard 16 / ISP.)
  - **Public mutable field** — encapsulate behind a behaviour-named method. (OOP fundamentals — encapsulation.)
  - **High-level service constructing a concrete dependency inside its body** — inject the abstraction; wire the concrete at the composition root. (Standard 17 / DIP.)
  - **Subtype that throws an error type the supertype does not declare**, or strengthens a precondition — fix the subtype or the interface contract. (Standard 15 / LSP.)
  - **Two unrelated reasons one class would change** — split into two classes. (Standard 13 / SRP.)

### 4. Run the pre-completion checklist before claiming done

Always copy the checklist from the canonical document into a TodoWrite list and tick each item with evidence (lint output, test output, links to the constants/types reused). The checklist is non-negotiable; do not narrate around a failing item — fix it.

Failing the checklist means the work is not done.

### 5. Lint errors take priority

If linter or type errors are present anywhere in code you touched, fix them **before** writing more logic. New code on top of unresolved lints is considered an unfinished change.

## Anti-patterns to refuse

- "I'll add a new file / service / module for this" — when extending an existing one fits, extend it; a new file needs a one-line justification that no existing owner fits.
- "I'll add a base class / abstraction / generic layer we might reuse later" — YAGNI; build for the requirement in front of you, generalise only on the second concrete caller.
- "More code is safer / shows the work" — the smallest correct diff a reader can follow wins; new files and lines are a cost, not a deliverable.
- "I'll write a new helper that does almost what the existing one does" — extend the existing helper (or its signature) instead of shipping a near-duplicate.
- "Let me just start coding the obvious approach" — first weigh the candidate shapes; the first idea is usually the most additive one.
- "We'll keep the old path for backward compatibility" — only if the spec explicitly asks for it.
- "I'll use `Record<string, any>` for now" — define the real type now.
- "Quick try/catch around the whole function" — wrap only the throwing call; map to a domain error.
- "I'll just inline this constant; it's only used here" — if it represents a domain concept, it belongs in the canonical constants file.
- "Generic code can import this provider helper just this once" — no. Invert the dependency.
- "I'll put this new constant in a new `<feature>.constants.ts` next to the existing `<module>.constants.ts`" — extend the canonical file instead.
- "I'll create a `<class-or-method>.unit.test.ts` next to the existing `<source-file>.unit.test.ts`" — add a sibling `describe(...)` block in the canonical test file instead.
- "I'll add another `case "newProvider":` to the existing `switch`" — register the new provider as a strategy in the registry; the dispatcher does not change.
- "A quick `instanceof` check is fine here" — no. Move the branch behind a polymorphic interface method.
- "I'll just extend the existing class to add this behaviour" — compose the new behaviour as a collaborator instead, unless the base class is framework-mandated.
- "One `Repository` with thirty methods is simpler than five small ports" — the consumer never depends on methods it does not use; split per role.
- "The high-level service can `new StripeProvider()` directly inside the method" — inject the abstraction; wire the concrete at the composition root once.

## Reference

- Canonical: [`~/.cursor/engineering-standards.md`](~/.cursor/engineering-standards.md).
- Workspace-level rules at `<repo>/.cursor/rules/*.mdc` (when present) pin tech-stack-specific guidance and known-debt entries; they win on conflicts within that repo.
