# Scalable Backend Design

This is the canonical scalable-backend-design document. Every contributor — human or agent — walks the questionnaire below before producing the design and applies the primitives below as the contract every backend service follows.

## The 7-step questionnaire

Walk these seven steps in order before producing any backend or distributed-AI design. Every step gets an answer in the deliverable, even if briefly. Silence on a step is a hole in the design.

1. **Workload shape.** Concurrent users / sessions, requests-per-second, p95 / p99 latency targets, peak vs average, hot keys, fan-out shape, payload size distribution.
2. **State and consistency.** What must survive a crash mid-operation, what is idempotent, what is OK to lose. Strong vs eventual consistency boundaries. Read-after-write expectations.
3. **Failure modes.** Upstream timeout, partial failure, schema drift, network partition, deploy mid-flight, dependency outage, slow consumer, poison message.
4. **Idempotency and dual-write.** Mutations that must be exactly-once, the idempotency key derivation, the outbox boundary, the dual-write reconciliation strategy.
5. **Event delivery and ordering.** Per-key ordering, exactly-once vs at-least-once, retry semantics, dead-letter handling, partition strategy, consumer groups.
6. **Observability.** RED metric per layer, correlation IDs threaded end-to-end, trace fields, log destinations, sampling strategy under load, alert thresholds.
7. **Safe failure / blast radius.** What happens when X is down, what gets escalated, tenant isolation boundary, blast-radius caps (per-tenant rate limits, per-shard pools, circuit breakers).

## The 12 primitives

These are the contract every backend service follows. Name a primitive in the design even when the answer is "we do not need this and here is why" — silence is a hole.

1. **Idempotency keys** for every mutation, derived from a content hash plus a tenant scope so retries collapse safely.
2. **Transactional outbox** for any "must persist exactly once" path that must not be lost when the process crashes.
3. **Idempotent consumers** for replayed events and retried invocations.
4. **Circuit breakers** around every external upstream, with explicit degraded-mode fallback responses when the breaker is open.
5. **Retries with backoff + jitter** with an explicit budget per call class. Any "single attempt, no retry" call is named in the design as a deliberate choice.
6. **Bulkheads** — separate connection pools / worker pools per upstream so one slow vendor cannot starve the rest.
7. **Backpressure** on streaming and queue-based paths so a slow consumer cannot pin producers.
8. **Graceful shutdown** — drain in-flight requests before exit, refuse new ones, signal the load balancer.
9. **Liveness vs readiness** — readiness gates on persistence + critical-upstream reachability; liveness is purely process health.
10. **Caching strategy** — explicit per cache (request, response, embedding, classifier output, prompt), with eviction and invalidation policy.
11. **Observability** — RED, correlation IDs, distributed tracing, log sampling under load, dashboards.
12. **Forward-only migrations** for any persistence schema. No "rollback by reverting the migration" — design the change to be safely deployable mid-flight.

## Application to AI / LLM systems

When designing an LLM-driven service, the 12 primitives apply unchanged. Six AI-specific extensions go on top:

- **Token-budget control** per turn and per session, with hard cut-off and a graceful truncation strategy.
- **Prompt-caching layout discipline** (static system block first, dynamic context after) verified by a periodic cache-hit-rate metric.
- **Cost guardrails** — per-tenant token quotas, model downshift on quota pressure, structured-output preferred over JSON parsing.
- **Model A/B / multi-armed-bandit routing** — never two parallel codepaths "for backward compat", always one canonical path with a routing key and a metric per arm.
- **Eval harness as a first-class deliverable** — golden grid + adversarial critique + drift probes. The design is incomplete without one.
- **Drift detection** on classifier inputs and upstream response shapes — periodic probe diffs live responses against recorded fixtures.

## Definition of done for a design

- The 7 questionnaire steps are answered (briefly is fine).
- Each of the 12 primitives is addressed (including "not needed because" answers).
- For AI services, the 6 AI extensions are addressed.
- Capacity model: at least order-of-magnitude numbers for tokens / second, requests / second, persistence growth.
- Failure-mode matrix: row per upstream, column per failure type, cell per behaviour.
- Eval / verification plan named, with success thresholds.
- Cost model (when relevant) named.
- All ambiguities surfaced via `AskQuestion` or `cursor-checkpoint`; no silent defaults.
