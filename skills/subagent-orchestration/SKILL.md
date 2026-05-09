---
name: subagent-orchestration
description: Discover registered subagents, build the dependency graph for the current task, dispatch by topology, and relay clarifying questions from subagents to the user. Use whenever the user gives a non-trivial coding, design, deployment, audit, or review task.
---

# Subagent orchestration

This skill defines how the parent Cursor agent discovers, dispatches, and relays for custom subagents — and the inviolable rule that any subagent's clarifying question is surfaced to the user verbatim.

## Canonical ask-don't-assume boilerplate

Every custom subagent must include this paragraph in its system prompt, character-for-character:

> When any parameter in the user's request is ambiguous, you must emit a `cursor-checkpoint` block to the parent (per the schema in `~/.cursor/skills/subagent-orchestration/SKILL.md`). You must not pre-answer your own clarifying questions, must not silently pick defaults, and must not proceed past an unconfirmed assumption on any decision touching credentials, irreversible operations, scope of work, public API shape, or destination of a write. The parent will surface the question to the user and resume you with the answer.

This is the canonical source of truth for the wording. The same paragraph appears in `~/.cursor/agents/ai-engineer.md` (Section 2.8) and in any future custom subagent.

## When to use this skill

For non-trivial tasks: implementation, design, deployment, audit, review, debugging that spans multiple subsystems. Trivial tasks (typo, single-line lint fix, doc tweak, single-token rename) skip the procedure entirely — handle them directly.

## Procedure

The procedure is discovery-driven and dataflow-driven. The roster of subagents is a runtime input; the registered list changes over time. Do not hard-code subagent names.

1. Discover. List registered subagents under `~/.cursor/agents/` (and `<workspace>/.cursor/agents/` if present). Read each agent's frontmatter — specifically `produces`, `consumes`, and `description`. Build a capability index from artefact-type to producer agents.
2. Identify the terminal artefact(s) the user's task requires (`code-diff`, `architecture-doc`, `lld-plan`, `prd`, `deploy-artefact`, `review-report`, `bug-diagnosis`, etc. — see the vocabulary section below). Identify which artefacts are already provided by the user (uploaded files, repo `.cursor/plans/`, prior chat context, existing repo source).
3. Build the dependency graph for THIS task by walking backwards from the terminal artefact through the capability index. Stop at leaves that are already provided. Different tasks produce different graphs.
4. Dispatch by graph topology. Run nodes whose dependencies are satisfied; multiple ready nodes run in parallel via concurrent `Task` calls in a single message. Sequential vs parallel falls out of the graph, not from a separate ruleset.
5. No registered producer for a needed artefact, ambiguous tiebreak between producers, cyclic graph, or terminal artefact that does not fit the vocabulary — ask the user via `AskQuestion`. Do not substitute or invent.

## Relay rule (inviolable)

When any subagent returns output containing a fenced code block whose info-string is `cursor-checkpoint`, your first action must be to relay the embedded question to the user via the `AskQuestion` tool, with the subagent's `question` and `options` verbatim.

- Do not assume an answer.
- Do not paraphrase the question.
- Do not take any other tool action before the user responds.
- After the user answers, resume the same subagent with `Task(subagent_type=<same>, resume=<agent_id>, prompt=<answer prepended to a brief continue-instruction>)` — never start a fresh instance of the same subagent for the same task.
- Other graph nodes already in flight continue while the paused node waits.

The relay rule applies to any subagent that emits the `cursor-checkpoint` block, current or future. You do not need a list of which subagents emit it; the marker is the trigger. A `subagentStop` hook at `~/.cursor/hooks/relay-subagent-checkpoint.sh` injects a `followup_message` reminding you of this rule the moment a subagent returns with the marker — but the rule holds even when the hook is unavailable.

## `cursor-checkpoint` block schema

Subagents emit clarifying questions in a fenced block tagged `cursor-checkpoint`. The block body is YAML. Required fields:

- `question` — the clarifying question to surface to the user, verbatim, in plain prose.
- `options` — list of answer options. Each option has `id` (short stable identifier) and `label` (display text, in complete sentences).

Optional fields:

- `context` — one or two sentences explaining why the question matters and what hinges on the answer. The parent may include this in the `AskQuestion` prompt as additional context.
- `allow_multiple` — boolean; defaults to `false`. Set to `true` if the user can pick more than one option.

Example shape (not enclosed in three backticks here so the example does not look like a real checkpoint to the parent):

    ~~~cursor-checkpoint
    question: "Which judge model should the eval harness use?"
    options:
      - id: gpt-4o
        label: "Use gpt-4o (lower judgment variance, ~10x output-token cost)."
      - id: gpt-4.1-mini
        label: "Use gpt-4.1-mini (cheaper and faster, slightly higher variance)."
    context: "The judge model affects per-run flake rate and per-run cost. We expect ~360 scenarios per run."
    ~~~

The parent maps the `cursor-checkpoint` block to an `AskQuestion` call where `prompt` is `question` (with `context` appended in italics if present), and `options` is the verbatim list of `{id, label}` pairs.

## Vocabulary contract

Use these artefact-type names in `produces` / `consumes` frontmatter so the dependency graph compiles cleanly:

- `prd` — product requirements doc.
- `architecture-doc` — high-level system context, components, data flow.
- `lld-plan` — low-level design / implementation plan.
- `distributed-design` — capacity, scaling, failure modes.
- `eval-design` — golden grids, critique scenarios, drift probes.
- `code-context` — read-only source / repo context for downstream agents.
- `code-diff` — produced by implementer agents.
- `review-report` — produced by reviewer agents.
- `bug-diagnosis` — produced by debug agents.
- `deploy-artefact` — produced by deploy agents.

If you need a new artefact type, add it here first and update every consumer / producer in the same change — the dependency graph compiles by name match, so a typo silently disconnects nodes.
