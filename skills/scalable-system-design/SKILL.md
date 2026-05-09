---
name: scalable-system-design
description: Apply the canonical scalable-backend-design doc (`~/.cursor/scalable-backend-design.md`) when designing a new service, integration, async pipeline, caching layer, distributed AI system, or migration. Walk the 7-step questionnaire and apply the 12 primitives before producing the design.
---

# Scalable system design

Read the canonical document at `~/.cursor/scalable-backend-design.md` whenever designing a new service, integration, async pipeline, caching layer, AI / LLM service, or migration.

## Procedure

Walk the 7-step questionnaire below before producing the design. Then for each design, name every one of the 12 primitives (including "we do not need this and here is why" answers).

### 7-step questionnaire

1. Workload shape — concurrent users / sessions, requests / second, p95 / p99 latency targets, peak vs average, hot keys, fan-out shape.
2. State and consistency — what survives a crash, what is idempotent, what is OK to lose, read-after-write expectations.
3. Failure modes — upstream timeout, partial failure, schema drift, network partition, deploy mid-flight, slow consumer, poison message.
4. Idempotency and dual-write — exactly-once boundaries, idempotency-key derivation, outbox boundary, reconciliation.
5. Event delivery and ordering — per-key ordering, at-least-once vs exactly-once, retries, dead-letter, partition strategy.
6. Observability — RED metrics per layer, correlation IDs threaded end-to-end, trace fields, log destinations, sampling.
7. Safe failure / blast radius — degraded behaviour when X is down, escalation, tenant isolation, blast-radius caps.

### 12 primitives (the contract)

1. Idempotency keys.
2. Transactional outbox.
3. Idempotent consumers.
4. Circuit breakers.
5. Retries with backoff + jitter.
6. Bulkheads.
7. Backpressure.
8. Graceful shutdown.
9. Liveness vs readiness.
10. Caching strategy.
11. Observability (RED + correlation + tracing).
12. Forward-only migrations.

### AI-specific extensions (apply on top, for LLM systems)

- Token-budget control per turn and per session.
- Prompt-caching layout discipline (static system block first).
- Cost guardrails (per-tenant quotas, model downshift).
- Model A/B / multi-armed-bandit routing.
- Eval harness as a first-class deliverable.
- Drift detection on classifier inputs and upstream response shapes.

## Ask, do not assume

Surface every ambiguous decision via `AskQuestion` or `cursor-checkpoint` — see `~/.cursor/rules/ask-dont-assume.mdc`. Naming a constraint before picking a pattern is the design's most important step; do not ship a pattern in search of a problem.

## Definition of done for a design

- 7 questionnaire steps answered.
- 12 primitives addressed.
- For AI systems, 6 AI extensions addressed.
- Capacity model with order-of-magnitude numbers.
- Failure-mode matrix.
- Eval / verification plan with success thresholds.
- Cost model (when relevant).
- Zero ambiguities left as silent defaults.
