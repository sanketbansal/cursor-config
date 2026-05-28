---
name: external-context-discovery
description: Use whenever a non-trivial task plausibly benefits from context that lives outside the local repo — tickets, design mocks, dashboards, schemas, chat threads, API specs, documents, vector indexes, runtime metrics. The skill teaches the runtime procedure for discovering whichever MCP servers are enabled on the user's machine, building a capability index from the tools' own descriptions, matching the task's information needs to those capabilities, calling MCP tools safely (read-first, schema-first, ask before any write), and degrading gracefully when no MCP fits. Project-agnostic, machine-agnostic, and roster-agnostic — every named server, every tool, and every capability class is read from disk at runtime, never hard-coded in this skill or in any agent that loads it.
---

# External-context discovery

This skill is the canonical runbook every custom subagent (and the parent Cursor agent) loads when a task plausibly needs information that does not live in the local repo — issue trackers, documentation systems, design tools, dashboards, observability backends, databases, vector stores, chat archives, API specs. The runbook is dataflow-driven and roster-agnostic: it tells the agent how to learn what MCP capabilities exist on the current machine, how to pick the right one for the current task, and how to call it safely. It never names a specific MCP server.

Two non-negotiables sit at the top because they are the failure modes this skill exists to prevent:

1. **Never hard-code an MCP server name.** No agent that loads this skill encodes "use the Atlassian MCP", "search Slack", "fetch from Figma". Discovery is runtime-driven from the user's installed roster. The same agent body runs unchanged whether the user has zero MCPs, one MCP, or twenty.
2. **Never call a write-class MCP tool without explicit user confirmation.** Creating a ticket, posting a comment, sending a message, modifying a design, mutating a dashboard, writing to a database are all irreversible operations — they fall squarely under the universal `ask-don't-assume` policy at `~/.cursor/rules/ask-dont-assume.mdc`. Read-only fetches are fine to do proactively for context-gathering; writes always require a `AskQuestion` (parent) or `cursor-checkpoint` (subagent) round-trip first.

## When to use this skill

Trigger on any of:

- Writing a PRD, BRD, spec, or feature design where prior decisions, related tickets, or existing user research likely exist outside the repo.
- Producing an architecture document, ADR, or design review where current production behaviour (latency, error rate, hot paths) or prior architectural decisions matter.
- Producing an LLD plan or implementation that references an external ID (ticket key, design mock, API spec, dashboard panel, vector index, feature-flag name).
- Diagnosing a bug, incident, or regression where runtime evidence lives in an observability or logging system.
- Auditing or reviewing code where compliance, ticketing, or design context shapes the verdict.
- Planning a rollout where deploy history, current dashboards, alert state, or CI history shape the safe-rollout window.

Skip when the task is purely local — typo, comment, single-token rename, one-line lint fix, refactor whose entire context is the local source tree. The cost of discovery is small but not zero; do not run it when the task gains nothing from it.

## Genericness invariant

The first time this skill is loaded for a task, write down (mentally or in your TODO list) the answer to a single check question: **"If the user had a different MCP roster than this machine has, would my plan still produce the same shape of result?"** If the answer is no, the plan has coupled to specific servers and must be rewritten to depend on capabilities, not servers. Capabilities are inferred from each tool's `description` field at runtime; servers are not named in reasoning, code, or deliverables.

## §1 Discovery procedure

Run this when the trigger fires. The procedure is filesystem-driven, so it runs identically on every machine that has the Cursor IDE.

1. **List the per-workspace MCP descriptor folder.** Cursor maintains one directory per enabled MCP server at `~/.cursor/projects/<workspace>/mcps/<server>/`. Glob `~/.cursor/projects/*/mcps/*/SERVER_METADATA.json` (or the workspace-scoped path the parent already knows) to enumerate servers. Treat zero matches as "no MCPs installed" — that is a valid state; proceed without external context.
2. **Cross-check against the agent's system-prompt MCP listing.** Cursor injects an `<mcp_file_system>` block into every agent's effective system prompt that enumerates enabled servers. Use it as a sanity check against the disk discovery. When the two diverge, trust the disk listing (it is sourced from the same Cursor state but is the canonical schema source).
3. **Read each server's descriptor surface.** For every server discovered in step 1:
   - Read `SERVER_METADATA.json` to learn the server's purpose and any global properties.
   - Glob and read `tools/*.json` to learn the tool schemas. Each tool JSON contains `name`, `description`, and `arguments` (a JSON Schema for the parameters).
   - Glob and read `resources/*.json` when present (resources are read-only data surfaces; some MCPs expose data only via resources rather than tools).
4. **Build the in-context capability index.** The index maps domain-language **capability classes** to the concrete MCP tools that can serve them. Capability classes are inferred from each tool's `description` field by inspection, not chosen from a closed list. Typical classes that emerge from reading descriptions are: issue tracking, document storage, design assets, time-series metrics, log search, chat / messaging, database / data layer, vector / semantic search, API specification, browser automation, file storage, secret retrieval, CI / deploy history. New classes appear naturally when new MCP servers are installed; never force a tool into a pre-existing class if its description does not fit.
5. **Cache the index for this task only.** A subsequent task triggers a fresh discovery — the roster may change between tasks (the user may install or remove plugins, switch workspaces, etc.).

## §2 Need-to-capability matching

Once the capability index is built, work out **what** the task needs from external context.

1. **Identify the task's information needs in domain language.** Ask "what would a senior practitioner pull up in another tab to do this well?". Examples (still domain language, no server names): "the open tickets in the touched domain", "the most recent design mock for this screen", "the current p99 of the touched endpoint", "the schema of the table the plan modifies", "the prior architectural decision that constrains this design".
2. **Match each need to one or more capability classes** in the index. The matching is fuzzy and description-based — a need for "open tickets" maps to whichever class the index built from tools whose descriptions talk about issues / tickets / bugs / work items.
3. **Resolve to a concrete tool only at call time.** Within a matched class, pick the specific tool whose schema fits the need (e.g., a "search" tool for an exploratory need, a "get by ID" tool when the user supplied a key). The choice is per-call, not per-task.
4. **Resolve ambiguity by asking, not by guessing.**
   - If a need has **zero** matching capability classes → ask the user (`AskQuestion` / `cursor-checkpoint`) to paste the data, or proceed without it and call out the gap explicitly in the deliverable.
   - If a need has **multiple** plausibly-matching classes → ask the user which class to use. Do not pick silently.
   - If multiple servers in the same class look equally good (e.g., two ticketing systems installed) → ask the user which to query.

## §3 Calling protocol

Mandatory invariants for every MCP call. Skipping any of these is a contract violation.

1. **Read the tool's schema before calling.** Open the `tools/<tool>.json` for the chosen tool with the `Read` tool. Verify the parameter names, types, and required fields. The standard `CallMcpTool` rule in the workspace's MCP filesystem documentation is non-optional: *always check the schema first*. Tool schemas evolve; rely on the disk descriptor, never on memorised parameters from a prior task.
2. **Authenticate on demand only.** If a tool returns an authentication or authorisation error, run `mcp_auth` for that server, then retry the original call once. Never call `mcp_auth` proactively (it has UI side-effects for the user) and never authenticate against more than one server in parallel.
3. **Bound the fan-out.** The default budget is **at most 3 calls per need-class per task**. If a genuine need requires more, ask the user before continuing (`AskQuestion` / `cursor-checkpoint`). Wide exploratory searches without a driving question waste quota and frequently surface noise.
4. **Use resources for bulk reads where present.** Some MCPs expose their data as resources rather than tools. Prefer the `ListMcpResources` / `FetchMcpResource` path for bulk reads; that path is cheaper, deterministic, and avoids LLM-shaped argument errors.
5. **Cite what you fetched.** Every artefact the agent produces that incorporates MCP-fetched context cites the source (ticket key, document URL, dashboard panel, mock frame, schema name) inline. The reader must be able to verify the cited fact without re-running the agent.
6. **Treat MCP output as input, not as truth.** External systems can be stale, partially permissioned, or wrong. When MCP output contradicts the user's stated intent or the repo state, surface the contradiction (one focused question) rather than picking a side silently.

## §4 Failure and degradation

External calls fail. The procedure assumes failure and degrades cleanly.

- **Transient tool error** (timeout, 5xx, network blip) → one retry with backoff is acceptable; a second failure surfaces the issue to the user without further attempts. Do not enter a retry loop.
- **Permanent tool error** (401, 403, 404, schema mismatch) → stop, surface the error verbatim to the user, and ask whether to proceed without that context or to fix the issue first.
- **No MCP fits a need** → either (a) ask the user to paste the relevant context, or (b) proceed without it and call out the gap explicitly in the deliverable's "Sources of truth" / "Open questions" section. **Never fabricate** the missing context.
- **Quota exhaustion / rate-limit** → stop, report the limit to the user, ask whether to wait or to proceed without further calls.
- **Returned data is empty when the user expected results** → do not loop. Surface the empty-result to the user and ask whether the search was scoped wrong, the data does not exist, or permissions are limiting the view.

## §5 Privacy and write-safety

The default mode is **read-only opportunistic fetch**. Anything that mutates external state is a write-class operation under the `ask-don't-assume` rule.

- **Reads** (search, fetch, get, list, describe, query) — fine to run proactively for context, subject to the §3 fan-out budget. Cite what was read in the deliverable.
- **Writes** (create, update, delete, post, send, comment, modify, attach, transition, move, archive, share) — always require an explicit user confirmation via `AskQuestion` (parent) or `cursor-checkpoint` (subagent) before the call. The confirmation states the target system in generic terms (e.g., "post a comment to the linked ticket") and the exact content to be written. The agent waits for the user's response before invoking the tool. This is not a once-per-task gate; every distinct write is its own checkpoint.
- **Sensitive reads** — when a read involves a credential surface (secret managers, key vaults, identity providers) or a PII surface (customer records, employee data), treat the read itself as write-class for confirmation purposes: ask before fetching, name the data class being touched. The user may pre-authorise a class for the duration of the task; the pre-authorisation must be explicit.

## §6 Anti-patterns to refuse

- **Hard-coding a server name.** "I will use the Atlassian MCP" / "search Slack for ..." / "fetch from Figma" in any agent prompt, plan, or rationale. Always name the **capability class** ("issue tracking", "chat / messaging", "design assets") and resolve to a concrete server at call time.
- **Calling MCP because it exists.** A discovered tool is not a directive to use it. Only fetch context that the task genuinely needs.
- **Skipping the schema read.** Invoking `CallMcpTool` from memory of a prior task's parameters. Schemas evolve; the disk descriptor is the source of truth.
- **Treating one transient error as definitive.** "MCP failed; we'll work without it" after one timeout. Retry once with backoff before degrading.
- **Inventing tools that are not in the descriptor folder.** If a need has no match in the index, the answer is to ask the user — not to call a tool name that "should" exist.
- **Routing internal data through a write-class MCP call without permission.** Posting a draft PRD into the user's ticketing system, sending an auto-generated summary to a chat channel, modifying a dashboard. Every write is a checkpoint.
- **Fan-out without a budget.** Calling fifteen search variants "in case one returns something". Three per need-class is the default cap; more requires a user-approved budget.
- **Citing nothing.** Producing a deliverable that incorporates MCP-fetched facts without inline citations to the source ticket, document, dashboard, or schema. The reader cannot verify and the audit trail evaporates.

## §7 Worked examples (generic — no server names)

Each example illustrates the procedure for one role's typical needs **without naming specific servers**. Every example assumes a different MCP roster could produce a different concrete choice while the procedure remains identical.

### Product manager writing a PRD

1. Discovery returns several capability classes — assume issue tracking, document storage, chat / messaging, and design assets are present (specifics vary by machine).
2. Information needs: prior PRDs / specs in the same domain, open and recently closed tickets touching the domain, recent decisions / threads in chat, current design mocks for the screens the PRD covers.
3. Match each need to its class; resolve to specific tools per call (a "search documents" tool, a "search tickets" tool, etc.).
4. Read-only fetches, ≤ 3 per class, cite each into the PRD's "Sources of truth" section.
5. If a need has no matching class (e.g., no chat MCP is installed), ask the user to paste relevant threads or proceed and call out the gap in the PRD's "Open questions".

### Principal engineer designing for an SLA

1. Discovery returns classes including time-series metrics, log search, document storage, and database / data layer (assumed; varies).
2. Information needs: current p99 of the touched endpoint, the failure rate over the last 30 days, the prior ADR that constrains this design, the current schema of the table the design modifies.
3. Match → resolve → read-only fetch with citations. The architecture doc's "Architectural drivers" section quotes the current numbers; the ADR-references section links to the prior ADR.
4. If no observability MCP is present, the architecture doc explicitly notes "current p99 not retrievable; the design assumes the PRD's target" and surfaces the gap as a Checkpoint-A question.

### Staff engineer planning a refactor

1. Module structure is usually accessible via local repo tools; MCP need is narrower — open tickets that touch the module, API contracts, prior refactor decisions.
2. Match → resolve → cite in the plan's "Sources of truth".
3. If the plan touches an external contract owned by another team (named in the PRD), search for the contract document; if not found, the plan's open-questions section asks for it.

### Software engineer implementing

1. The local repo state + the LLD plan are usually sufficient. MCP is consulted only when the plan **references** an external ID (e.g., the plan cites a ticket key for a regression scenario, or a feature-flag name).
2. Resolve each referenced ID via the matching capability class. If the reference is broken (ticket archived, flag retired), surface as a single blocking question per the agent's HITL protocol — do not silently work around the gap.

### DevOps planning a rollout

1. Needs: current dashboards for the touched service, recent deploy history, current alerts, CI history for the last N runs on the branch.
2. Match to time-series metrics, CI history, log search.
3. Read-only fetches with citations into the rollout plan's "Pre-deploy verification" and "Rollback signals" sections.
4. Any write (deploy approval, alert silence, dashboard annotation) is a separate user checkpoint per §5.

### AI engineer designing an LLM system

1. Needs: existing vector indexes (names, dimensions, ingest pipelines), prior AI-system epics or ADRs, current observability for the AI stack.
2. Match to vector / semantic search class, document storage, time-series metrics / log search.
3. Cite into the architecture doc's "Existing footprint" section.

### Claude-code relay

The Claude Code CLI is a separate process that does not have access to the Cursor-side MCP surface. The relay's job is to **pre-fetch** the task-relevant MCP context per §1–§3 and **inline the findings as prose** into the brief it constructs in `~/.cursor/agents/claude-code.md` `§2.3` step 1. Anything not in the brief is invisible to Claude Code; the relay does not get to assume Claude Code will "look it up itself".

## §8 Pre-completion checklist

Before declaring a deliverable done, walk this checklist. Failing any item means the work is not done.

- Discovery was run (or explicitly skipped because the task is purely local — and the skip is justified).
- Every information need is either satisfied via MCP, satisfied via user-pasted context, or explicitly called out as a gap.
- Every MCP fetch read the tool's schema before calling.
- Every MCP fetch is cited inline in the deliverable.
- No agent reasoning or deliverable text names a specific MCP server. (Capability classes are fine; concrete names are not.)
- Every write-class MCP call was explicitly confirmed by the user via `AskQuestion` / `cursor-checkpoint`. (If no writes were attempted, this item is trivially satisfied.)
- The fan-out budget was respected (≤ 3 calls per need-class) or an over-budget call was explicitly user-approved.
- The genericness invariant check at the top of this skill returns "yes" — the same plan would shape-equivalent on a different MCP roster.

## References

- The universal ask-don't-assume policy — `~/.cursor/rules/ask-dont-assume.mdc`. Write-class MCP calls fall under "credentials, secrets, auth scopes" and "irreversible operations".
- The subagent orchestration runbook — `~/.cursor/skills/subagent-orchestration/SKILL.md`. The parent agent's first-pass procedure now includes external-context discovery alongside subagent-roster discovery.
- The Cursor MCP filesystem (canonical home of tool descriptors at runtime) — `~/.cursor/projects/<workspace>/mcps/<server>/{SERVER_METADATA.json, tools/*.json, resources/*.json}`. The skill reads from this surface; it does not maintain a parallel list.
- The Cursor MCP tool surface (how agents actually invoke MCP) — `CallMcpTool`, `ListMcpResources`, `FetchMcpResource`, `mcp_auth`. The schema-first invariant applies to every call.
