# Scalable Backend Design (Canonical)

This is the global reference for system-design primitives every backend service should consider, regardless of language, framework, or cloud. The personal `scalable-system-design` skill triggers on architecture/design tasks and points at this file. Update this single document; do not duplicate the patterns.

> Companion to [`~/.cursor/engineering-standards.md`](engineering-standards.md). Engineering standards govern *how* code is written; this doc governs *what shape* the system has.

Every backend service runs at scale, with retries from upstream clients, partial failures from downstream dependencies, and at-least-once delivery from any messaging substrate. These primitives are the contract every service follows. **Name the constraint before picking a pattern; do not ship a pattern in search of a problem.**

---

## 1. Idempotency keys + DB-transaction enforcement

Every state-mutating endpoint accepts an `Idempotency-Key` (client-supplied UUID). The key is stored in the **same DB transaction** as the business write. On retry, the stored response is returned — the operation is not re-executed.

```ts
await db.transaction(async (trx) => {
  await trx("idempotency_keys").insert({ key, client_id, created_at: new Date() });
  const payment = await trx("payments").insert(payload).returning("*");
  await trx("outbox_events").insert({ aggregate_id: payment.id, event_type: "payment.completed", payload });
  return payment;
});
```

A Redis `SET NX EX` (or equivalent) dedup is a **fast-path optimization**, not a substitute for the DB unique constraint. The cache can fail; the DB constraint is the source of truth.

## 2. Transactional outbox for DB → message-bus atomicity

Publishing to a message bus (Kafka / SQS / RabbitMQ / NATS) **after** the DB commit is a dual-write problem: the DB commits, the publish fails, the downstream system never learns. Write the event to an `outbox_events` table in the **same transaction** as the business state change. A separate poller (or CDC stream like Debezium) reads the outbox and publishes.

If the transaction rolls back, the event is never published. If the publish fails, the row stays in the outbox and is retried. If the publish succeeds but the outbox status update fails, the event publishes again — which is fine, because consumers are idempotent (§3).

## 3. Idempotent consumers

Every async consumer must handle duplicates. Deduplicate by **business key** (e.g. payment ID, event ID), **not** by the broker's offset / message ID — those are not stable across rebalances or redelivery.

```ts
await db.transaction(async (trx) => {
  const inserted = await trx("processed_events")
    .insert({ event_id: msg.key, processed_at: new Date() })
    .onConflict("event_id").ignore().returning("event_id");
  if (inserted.length === 0) return;          // duplicate, already processed
  await applyBusinessUpdate(trx, msg.value);
});
await commitOffset(msg);                      // only after the transaction commits
```

The `processed_events` insert and the business write share **one** DB transaction. Offset / ack happens after the transaction. A crash anywhere keeps the event undelivered until the consumer restarts.

## 4. Circuit breaker on every remote dependency

Slow or failing dependencies amplify tail latency and consume upstream capacity. Wrap every remote call in a circuit breaker.

Suggested defaults: open at 50% failure rate over 10 requests; half-open probe after 30s. When the circuit is open, the call fails fast (no waiting). Retries operate **inside** the breaker context — when the circuit is open, retries abort immediately rather than piling on.

## 5. Retries with exponential backoff + jitter

Only retry **idempotent** or **idempotency-keyed** operations. Cap the retry count and the total deadline. Add jitter to avoid thundering-herd retry waves.

```ts
async function withRetry<T>(fn: () => Promise<T>, attempts = 3): Promise<T> {
  let lastError: unknown;
  for (let i = 0; i < attempts; i++) {
    try { return await fn(); }
    catch (e) {
      lastError = e;
      if (!isTransient(e) || i === attempts - 1) throw e;
      const baseMs = 100 * Math.pow(2, i);
      const jitterMs = Math.floor(Math.random() * baseMs);
      await sleep(baseMs + jitterMs);
    }
  }
  throw lastError;
}
```

## 6. Bulkheads — resource isolation

Separate connection pools and worker pools per workload class so a noisy neighbor cannot starve the hot path. Example: API request handlers use one DB pool; cron / batch jobs use a second pool with its own size budget. A long-running batch query cannot exhaust the API pool.

## 7. Backpressure — bounded queues, shed load

Unbounded queues hide the failure until the heap explodes. Bound every in-flight queue (DB pool, async work queue, HTTP keep-alive). Above thresholds, reject or shed load with `429 Too Many Requests` or a queue-full error. Surface it as a real failure so capacity planning gets real signal, not a frozen request.

## 8. Graceful shutdown on `SIGTERM`

```ts
async function shutdown(signal: string) {
  logger.info("shutdown started", { signal });
  server.close();                                    // stop accepting new HTTP
  await consumer.disconnect();                       // commit pending offsets / acks
  await db.destroy();                                // close DB pool
  await cache.quit();                                // close cache client
  logger.info("shutdown complete");
  process.exit(0);
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT",  () => shutdown("SIGINT"));
```

No `process.exit(0)` from request handlers. No `--forceExit` in production runtime (it masks shutdown bugs).

## 9. Liveness vs readiness — they are not the same probe

- **Liveness**: process is up and responsive. If liveness fails, the orchestrator restarts the pod. Endpoint returns 200 if the event loop responds.
- **Readiness**: process is ready to serve. Returns 200 only when DB pool, cache, and message-bus client are connected AND the service has finished startup. The load balancer routes only on readiness.

Two separate endpoints (`/healthz` and `/ready`), two separate handlers. Don't conflate them.

## 10. Caching strategy — name keys, TTLs, invalidation

Cache-aside is the default. Document for every cache: key shape (versioned, namespaced), TTL, invalidation paths (write-through, TTL-only, event-driven), and what happens on cache miss vs cache failure (fall through to DB; degrade, do not fail). Cache + read replicas protect the primary DB.

Versioned key shape: `v<version>:<service>:<entity>:<id>`. Bumping `v1` → `v2` ages out old shapes via TTL after a schema change.

## 11. Observability — RED + correlation + tracing

Every service emits:

- **Structured JSON logs** with correlation/request ID propagated via async-context (e.g. `AsyncLocalStorage`, Go `context.Context`, Python `contextvars`).
- **RED metrics** per endpoint and per consumer: **R**ate, **E**rrors, **D**uration (p50 / p95 / p99). Dashboard them.
- **Distributed tracing** via `traceparent` header propagation across HTTP and message-bus boundaries.

If an incident requires `grep`-ing across multiple services without correlation IDs, the observability story has failed. Fix it before shipping the next change.

## 12. Forward-only schema migrations

No `down()` body that does damage. Three-step deploy for any breaking change:

1. Deploy the **additive** migration (new column nullable, new table, new index — `CREATE INDEX CONCURRENTLY` to avoid table locks).
2. Deploy the **code** that writes/reads the new shape (dual-write if needed).
3. Deploy the **cleanup** migration (drop old column, mark required) only after all running code uses the new shape.

A failed deploy must be safe to roll back at the code level. The migration history is monotonic forward.

---

## Design walkthrough — answer all 7 before writing the design

When designing a new service, integration, async pipeline, or cache layer, walk these questions in order. The personal `scalable-system-design` skill prompts this walkthrough automatically.

### 1. Workload shape

- Read-heavy or write-heavy?
- Sustained throughput (RPS / events per second) at p50, peak (≥3×), and worst case (10×)?
- Latency budget per operation (p95, p99)?
- Synchronous (request / response) or asynchronous (event / queue)?
- Bounded payload size, or arbitrary?

If the answer is "I don't know", flag it as an assumption, pick a defensible default, and mark it for confirmation.

### 2. State + consistency

- Where does state live? RDBMS / cache / message bus / external system / in-memory?
- Is read-your-writes required? (Caches break this if not invalidated correctly.)
- Per-entity ordering required? (If yes, partition by entity key.)
- Multi-row mutation? Wrap in a DB transaction with row locks on the rows you intend to mutate.
- What consistency level is acceptable per operation — strong, eventual, monotonic?

### 3. Failure modes

For each external dependency (DB, cache, message bus, third-party API, internal service), answer:

- What happens if it is **slow** (responds in seconds instead of ms)? → timeouts + circuit breaker (§4).
- What happens if it is **down**? → retry policy with backoff + jitter (§5), fallback (degrade gracefully or fail fast).
- What happens if a single call **partially succeeds** (DB committed, message-bus publish failed)? → see §1, §2.
- What's the blast radius of a single dependency failing — does it take this entire service with it? → bulkheads (§6).

If a dependency is on the hot path with no fallback, the service inherits that dependency's availability. Note this explicitly.

### 4. Idempotency + dual-write

- Mutating endpoint? → require `Idempotency-Key` header, store in DB unique index in the same transaction as the business write (§1).
- Need to publish an event after a DB write? → use the **transactional outbox** pattern (§2). Never publish post-commit and hope.
- Consumer? → idempotent dedup by **business key**, not broker offset (§3).

### 5. Event delivery + ordering

- Which topic / queue / stream?
- Partition key? (Choose a stable business key — userId, accountId, orderId — so per-entity order is preserved.)
- At-least-once consumer with manual ack/commit only after successful processing.
- Retry / DLQ policy: max retries, transient vs permanent error classification, DLQ destination, headers to capture (`x-original-topic`, `x-retry-count`, `x-error-message`, `x-failed-at`).
- Schema versioning strategy (`{ "schema": "v1", "data": {...} }`).

### 6. Observability

- What metrics confirm the service is healthy? Per endpoint and per consumer: RED. Define what "healthy" means (target SLO).
- What logs prove a single request is correct end-to-end? Confirm `requestId` flows through structured logs (§11).
- What traces span service boundaries? `traceparent` header propagated on outbound HTTP and message-bus headers.
- What alerts fire when the SLO is missed? Alert on RED, alert on consumer lag, alert on DLQ depth — never alert on raw error counts (a single error during deploy is not an incident).

### 7. Safe failure / blast-radius bound

- What's the worst thing that can happen if this service is fully unavailable for 5 minutes?
- What's the worst thing if it is **lying** (returns success but didn't persist, or persists silently incorrect data)?
- What is the rollback path — code-only? Migration step needed? (Migrations stay forward-only — §12.)
- Graceful shutdown: SIGTERM → stop accepting → drain in-flight → close pools → exit (§8). Confirm the orchestrator's grace period exceeds drain time.
- Liveness vs readiness — two separate endpoints (§9). Confirm load balancer routes only on `/ready`.

---

## Anti-patterns this document blocks

- "We'll add idempotency later" for a mutating endpoint.
- DB write followed by message-bus publish without an outbox.
- Consumer with auto-commit on, or commit at message offset instead of "next" offset.
- Cache without a documented TTL, key shape, or invalidation path.
- New service with one health-check endpoint that does both liveness and readiness.
- Retries with no jitter, no max attempts, no deadline.
- "Designed for scale" without naming a target throughput / latency.
- Designing scalability for a workload that is genuinely small (e.g. an admin endpoint with 1 request / hour does not need a circuit breaker, retry queue, and DLQ — name the constraint, then pick the pattern).

## Companion documents

- [`~/.cursor/engineering-standards.md`](engineering-standards.md) — the universal 12 standards + pre-completion checklist; runs alongside this doc once implementation begins.
- [`~/.cursor/skills/scalable-system-design/SKILL.md`](skills/scalable-system-design/SKILL.md) — auto-trigger skill that runs the 7-step walkthrough before producing a design.
- Workspace-level `<repo>/.cursor/rules/scalable-backend-design.mdc` and tech-specific rules pin the exact tech-stack for that repo (Postgres pool sizing, Kafka commit semantics, Redis client choice, etc.).
