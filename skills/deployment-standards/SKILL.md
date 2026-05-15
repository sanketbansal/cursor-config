---
name: deployment-standards
description: Use whenever producing, reviewing, or modifying a deployment artefact — a Dockerfile or container image definition, a CI/CD workflow, Infrastructure-as-Code (Terraform, Pulumi, Helm, CDK, etc.), a package-manager script that drives build / deploy / rollback, a runtime process definition, or any rollout / release / observability-at-deploy concern. Project-agnostic; the skill teaches the method, not the stack. Trigger on tasks mentioning deployment, release, rollout, container, Dockerfile, CI/CD, pipeline, workflow, IaC, Terraform, Pulumi, Helm, GitHub Actions, GitLab CI, package-manager scripts, runtime process, liveness, readiness, secret management, observability-at-deploy, rollback, autoscaling.
---

# Deployment Standards

This skill is the universal-standards reference for anything that ships code from "written" to "running". It pairs with the `dev-ops` subagent (which is the two-phase driver that plans and implements) and with the project-specific `deployment-standards` rule (which pins the repo-local conventions).

> Load this skill together with the project's deployment-standards rule (usually at `<repo>/.cursor/rules/deployment-standards.mdc`) and with `engineering-standards` whenever you touch any artefact listed below.

## When to use this skill

Trigger on any of:

- Writing or modifying a Dockerfile, container image definition, or `.dockerignore`.
- Writing or modifying a CI/CD workflow (GitHub Actions, GitLab CI, Buildkite, CircleCI, etc.) or a composite action.
- Writing or modifying Infrastructure-as-Code for any cloud or orchestrator (Terraform, Pulumi, CDK, Helm, Kustomize, Cloud Formation, OpenTofu, etc.).
- Adding or modifying a `package.json` (or equivalent — `Makefile`, `pyproject.toml`, `Cargo.toml`) script that drives build / test / deploy / rollback.
- Designing or changing a runtime process (API, worker, cron, consumer, reconciler) — its boot order, shutdown order, probe contracts, scale profile.
- Wiring or changing observability at the deployment layer (log sinks, metrics scrape, trace propagation, alerts, deploy markers).
- Designing or changing secret management — where secrets live at rest, how they reach the process, how they rotate.
- Producing or reviewing a rollout plan, rollback plan, release cadence, or deploy approval model.

For backend system design at the code level (module hierarchy, idempotency, outbox, event shape), load the `engineering-standards` and `scalable-system-design` skills instead; this skill starts at the boundary where code hits deployment substrate.

## Core standards

The twelve deployment standards below are project-agnostic. Every project's `deployment-standards.mdc` refines them with repo-local paths and conventions; those are load-bearing on top of these.

### 1. Container immutability

Images are build artefacts. Nothing inside a running container mutates itself in production. State lives outside the container — managed datastores, object storage, cache clusters, secret managers. If the service needs writable storage, mount it explicitly and bound it.

### 2. Multi-stage build discipline

Every service image has at least two stages — one that installs / compiles dependencies and one that runs them. Three stages are preferred for typed languages: deps install → build → runtime. The runtime stage contains only what the process needs at runtime — no source, no dev dependencies, no caches, no build tools.

### 3. Pinned base images and locked dependencies

Base images are pinned by digest when possible, by patch-level tag at minimum. Floating tags (`:latest`, `:20`, `:alpine`) are banned — they make builds non-reproducible and hide supply-chain drift. Dependency manifests are locked (`package-lock.json`, `yarn.lock`, `Pipfile.lock`, `go.sum`, `Cargo.lock`) and enforced at install time (`npm ci`, `yarn install --frozen-lockfile`, etc.).

### 4. Least privilege

A non-root user in the runtime stage of every image. Read-only root filesystem where the stack supports it. In cloud IaC, every IAM principal has the narrowest action + resource scope it can do its job with — no wildcard actions, no wildcard resources, no "*" on sensitive services.

### 5. Environment parity

Local dev stands up the same process shape the cloud stands up — same process count, same wiring, same env-var names, same health-probe contracts, same ordering of startup. The local substitutes for managed services (Postgres-in-a-container, Redis-in-a-container, Kafka-in-a-container or an embedded alternative) are declared in the same IaC tool (or an equivalent compose / orchestrator manifest) so parity can be audited.

### 6. Secret boundary

Never baked into images. Never committed to the repo. Never printed to logs. In cloud environments, secrets live in a cloud secret manager (AWS Secrets Manager / SSM, GCP Secret Manager, Azure Key Vault, Vault, sealed-secrets, etc.) and are injected at runtime. In local dev, secrets live in a git-ignored override file. Every secret has a named rotation owner and a rotation cadence.

### 7. Observability at the deployment layer

- **Liveness** and **readiness** are two separate endpoints, not one shared probe. Liveness is cheap and dependency-free (the process responds to the event loop). Readiness flips true only after the dependencies the service requires to serve traffic are all healthy.
- **Structured logs** with correlation / trace IDs leave the process as JSON (or the equivalent structured format) and land in the central log sink.
- **Metrics scrape endpoint** exposes RED (Rate / Errors / Duration) per endpoint and per consumer, plus queue depth, pool saturation, and breaker state.
- **Tracing headers** (`traceparent` or equivalent) propagate across process boundaries.
- **Deploy markers** are emitted to the observability stack at every deploy so dashboards can overlay deploy events on latency / error graphs.

### 8. Rollback safety

Every deploy is reversible in one step — flip the image tag back, flip the IaC revision back, or run the rollback workflow. Image tags are immutable in the registry — no tag reuse. Schema migrations are forward-only; the engineering-standards rule governs migration body shape, and this skill wires migration execution into the rollout order.

### 9. CI/CD discipline

- **Pinned third-party actions** by commit SHA (or the platform's equivalent immutable reference). Tag-based `@v4` references are a supply-chain risk.
- **Secretless authentication** where the cloud supports it — OIDC from the CI runner to the cloud IAM role, no long-lived keys.
- **Explicit triggers and gates.** Every workflow states what it runs on (branch, tag, release, schedule, dispatch) and the gates it enforces (lint, type-check, tests, coverage floor, security scan, SBOM generation) before it publishes or deploys.
- **Production environment protection** — required reviewers, protected branches, protected environments, audit trail for approvals.
- **Concurrency groups** prevent overlapping deploys to the same environment.

### 10. Package-manager script hygiene

Every runtime process has a `start:<process>` and `dev:<process>` script (or the equivalent in the project's package manager). Scripts that cross environments are named with the environment (`deploy:<env>`, `infra:status:<env>`). No script hides privileged actions behind an innocuous name.

### 11. Cost-aware scaling

CPU / memory requests are right-sized to measured load — not picked from vibe. Autoscaling signals are real (RED metrics, queue depth, CPU saturation, custom business metrics with documented thresholds) — not instance count, not time-of-day unless the evidence justifies it. Minimum replicas are set with availability / blast-radius in mind; maximum replicas are bounded so a bad signal cannot burn the budget.

### 12. Reproducible, deterministic builds

Builds are deterministic across runners. Locked dependency manifests. No network fetches at image build time except through pinned registries. No timestamps, per-run UUIDs, or per-user state inside artefacts. Same inputs → same image digest (within the tolerances the build tool allows).

## Pre-completion checklist

Copy this literal checklist into a TodoWrite list whenever a deployment artefact is in scope. Tick each item with evidence (output, path, screenshot, dry-run log). A failing item is not done.

- [ ] Multi-stage image: build vs runtime boundary is named; runtime stage contains only what the process needs.
- [ ] Base image is pinned by digest (preferred) or by patch-level tag (minimum); no `:latest`, no `:<major>`-only tag.
- [ ] Non-root user is set in the runtime stage (`USER <app>` or equivalent); read-only root filesystem is enabled where the stack supports it.
- [ ] `HEALTHCHECK` is defined on the image (or the orchestrator probe set is documented when the image has no built-in healthcheck).
- [ ] Entrypoint boot order is documented and matches code: config → datastores → bus / queue → in-process workers → HTTP / cron listener → readiness flip.
- [ ] Shutdown order on SIGTERM is documented and matches code: stop new work → drain → commit offsets / close producer → close datastores → exit.
- [ ] Liveness and readiness are two separate endpoints; the orchestrator probe config reads both, not one.
- [ ] Every CI workflow has explicit triggers, gates (lint + type-check + tests + security scan), an artefact-publish condition, and a deploy approval model.
- [ ] Third-party actions are pinned by commit SHA; cloud auth uses OIDC (or secretless equivalent) where supported.
- [ ] IaC has local-dev parity (one-command bring-up standing up the same process shape) AND per-environment cloud definitions.
- [ ] Provider versions in IaC are pinned (exact or `~>` patch bracket); state backend is explicit.
- [ ] Every runtime process has `start:<process>` and `dev:<process>` scripts (or equivalent) in the project's package manager.
- [ ] Secret boundary is named: where each secret lives at rest, how it reaches the process, who rotates it and on what cadence.
- [ ] No secrets are baked into the image (`docker history` or equivalent inspection verified).
- [ ] `.dockerignore` (or equivalent) is in lockstep with `.gitignore`; `.env` / `.env.*` files are excluded from build context.
- [ ] Rollback path is documented as a concrete recipe; image tags are immutable; previous tag is still deployable.
- [ ] Observability: structured logs, RED metrics, traceparent propagation, deploy markers — all wired and reachable from every environment.
- [ ] Cost profile: CPU / memory are right-sized; autoscaling signal and thresholds are identified and justified.

## Placement discovery protocol

Before designing any new artefact or proposing a change, read the existing tree to establish the reuse baseline.

1. List every existing Dockerfile: `ls <repo>/**/Dockerfile*` and `ls <repo>/**/infrastructure/docker/`.
2. List every existing workflow: `ls <repo>/.github/workflows/` (or the project's CI directory — `.gitlab-ci.yml`, `.buildkite/`, `ci/`).
3. List every IaC module: `ls <repo>/templates/`, `ls <repo>/infrastructure/`, `ls <repo>/terraform/`, `ls <repo>/helm/`, `ls <repo>/k8s/`.
4. Open the project's `package.json` (or equivalent) and note every existing `start:*`, `dev:*`, `deploy:*`, `aws:*`, `gcp:*`, `infra:*` script — these are the naming convention the project already uses.
5. Open the project's `AGENTS.md` and `<repo>/.cursor/rules/deployment-standards.mdc` (or nearest equivalent). These pin the repo-local conventions this skill must respect.

New artefacts mimic the existing placement. Do not invent `docker/` at the repo root when the project already keeps images under `infrastructure/docker/`. Do not invent `.github/workflows/deploy.yml` when the project names workflows by environment (`deploy-<service>-<env>.yml`). Pattern-match first, name second.

## Self-check for project-agnosticism

When authoring or editing any deployment artefact that will be reused across projects — the `dev-ops` subagent body, this skill, or a shared template — run a leak-check against the token list the project considers project-specific. Typical examples: the monorepo or product name, individual service names, specific cloud service acronyms (container-orchestrator names, compute-runtime names), specific build-tool runners, specific Node-process launchers. The exact token list is owned by the project's workspace-level deployment-standards rule.

Invoke the check as:

```bash
rg -n "<pipe-separated-project-tokens>" ~/.cursor/agents/dev-ops.md ~/.cursor/skills/deployment-standards/SKILL.md
```

Any match indicates a project-specific leak that must be moved into a per-repo deployment-standards rule instead. A clean run returns the empty set.

## Anti-patterns to refuse

- "One-stage Dockerfile, copies source on top of the Node image" — leaks dev deps and source into runtime; use multi-stage.
- "Run the container as root so we can write to `/app`" — state belongs outside the container; fix the app, do not concede on root.
- "Use `:latest` on the base image; we'll pin later" — pin now.
- "Bake the secret into the image; it's only dev" — still leaks through `docker history`; inject at runtime.
- "One `/health` endpoint covers both liveness and readiness" — they have different semantics; split them.
- "Workflow runs on all branches; we'll add filters later" — adds now or the workflow gets disabled.
- "We use `actions/checkout@v4`; SHAs are noisy" — pin to SHA; Dependabot keeps them fresh.
- "Long-lived AWS access keys in a repo secret" — migrate to OIDC; the migration path is short.
- "No local-dev IaC; we can only reproduce in staging" — parity is not optional; it is a correctness property.
- "Image tag reused across deploys" — violates rollback-in-one-step; every deploy gets an immutable tag.

## References

- The project's workspace-level `deployment-standards.mdc` (repo-specific paths and naming conventions).
- The project's file-glob-scoped tech rules: Docker image rule, CI/CD rule, IaC rule.
- Companion skills: `engineering-standards` (code-level standards), `scalable-system-design` (system-design primitives — idempotency, outbox, circuit breakers, etc.).
- Driver subagent: `dev-ops` (two-phase plan-then-implement).
