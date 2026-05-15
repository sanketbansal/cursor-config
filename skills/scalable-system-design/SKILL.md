---
name: scalable-system-design
description: Use whenever designing a new backend service, integration, async pipeline, caching layer, or migration. Walks the design through a 7-step questionnaire (workload shape, state and consistency, failure modes, idempotency and dual-write, event delivery and ordering, observability, safe failure / blast-radius) and applies the 12 system-design primitives (idempotency keys, transactional outbox, idempotent consumers, circuit breakers, retries with backoff and jitter, bulkheads, backpressure, graceful shutdown, liveness vs readiness, caching strategy, observability, forward-only migrations). Always load before producing the design.
---

# Scalable System Design

This skill enforces the universal scalable-backend system-design primitives defined in the canonical document:

> [`~/.cursor/scalable-backend-design.md`](~/.cursor/scalable-backend-design.md)

**Always read the canonical document at the start of any design / architecture task** for a backend service. The canonical doc is the source of truth — if anything below conflicts with it, the canonical doc wins.

This skill runs alongside [`engineering-standards`](../engineering-standards/SKILL.md): that skill governs *how* code is written; this one governs *what shape* the system has.

## When to use this skill

Trigger on any of:

- "Design a new service / module / endpoint."
- "Add an integration with `<external provider>`."
- "Add an async / batch / scheduled / queue / message-bus pipeline."
- "Add caching for X."
- "Refactor X to scale to Y."
- "Migrate X to Y."
- "Plan an architectural change to a backend service."

## What to do

### 1. Load the canonical doc

Read `~/.cursor/scalable-backend-design.md` and surface the 12 primitives plus the 7-step design walkthrough into your working context.

### 2. Walk the 7 questions before producing the design

For each step, write the answer **explicitly in the design**. Do not skip a step because it "obviously doesn't apply" — write a one-line justification and move on.

1. **Workload shape** — read- vs write-heavy; sustained / peak / worst-case throughput; latency budget; sync vs async; payload size bounds. Mark unknowns as assumptions.
2. **State + consistency** — where state lives; read-your-writes requirements; per-entity ordering; multi-row mutation needs; consistency level per operation.
3. **Failure modes** — for each external dependency answer: what if it's slow, what if it's down, what if a single call partially succeeds, what's the blast radius.
4. **Idempotency + dual-write** — `Idempotency-Key` header and DB unique index in the same transaction; transactional outbox for DB → message-bus atomicity; consumers idempotent by business key.
5. **Event delivery + ordering** — topic / queue / stream choice; partition key; manual ack / commit only after success; retry / DLQ policy with structured headers; schema versioning.
6. **Observability** — RED metrics per endpoint and per consumer; structured JSON logs with correlation ID; distributed tracing across HTTP and message-bus; SLO-based alerting (not raw error counts).
7. **Safe failure / blast-radius** — worst case if unavailable; worst case if lying; rollback path (forward-only migrations); graceful shutdown on SIGTERM; liveness vs readiness as separate endpoints.

### 3. Output format

The design that comes out of this skill includes (at minimum) sections labelled:

```
## 1. Workload shape
...
## 2. State + consistency
...
## 3. Failure modes
...
## 4. Idempotency + dual-write
...
## 5. Event delivery + ordering           (or: "n/a — no async paths")
...
## 6. Observability
...
## 7. Safe failure / blast-radius bound
...
## Open questions / assumptions
- <items the team needs to confirm>
```

A reviewer should be able to read the design top-to-bottom and find where each scalability concern was addressed without searching for it.

### 4. Hand off to implementation

Once the design is approved, the [`engineering-standards`](../engineering-standards/SKILL.md) skill takes over for the implementation phase. Tech-stack-specific rules at `<repo>/.cursor/rules/*.mdc` (when present) provide the concrete contracts (Postgres pool sizing, Kafka commit semantics, Redis client choice, framework conventions, CI/CD patterns, etc.).

## Anti-patterns to refuse

- "We'll add idempotency later" for a mutating endpoint.
- DB write followed by message-bus publish without an outbox.
- Consumer with auto-commit on, or commit at message offset instead of "next" offset.
- Cache without a documented TTL, key shape, or invalidation path.
- New service with one health-check endpoint that does both liveness and readiness.
- Retries with no jitter, no max attempts, no deadline.
- "Designed for scale" without naming a target throughput / latency.
- Designing scalability for a workload that is genuinely small (e.g. an admin endpoint with 1 request / hour does not need a circuit breaker, retry queue, and DLQ — name the constraint, then pick the pattern).
- "We'll use exactly-once delivery" — exactly-once is mathematically impossible in a distributed system; design for at-least-once + idempotency.

## Reference

- Canonical: [`~/.cursor/scalable-backend-design.md`](~/.cursor/scalable-backend-design.md).
- Companion skill: [`~/.cursor/skills/engineering-standards/SKILL.md`](../engineering-standards/SKILL.md).
- Workspace-level rules at `<repo>/.cursor/rules/scalable-backend-design.mdc` and tech-specific rules pin the exact tech-stack contracts for that repo.
