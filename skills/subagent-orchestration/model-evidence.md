# Model evidence ledger

Volatile, dated evidence consumed by the model-routing procedure in `SKILL.md` §12. This file is **data, not policy**: the routing algorithm, quality floors, and qualification gates live in §12; this ledger only records what is currently known about currently-visible models, with sources and expiry dates.

Binding rules (from §12.8):

- **No permanent roster.** Records exist only for slugs observed in a live `Task`-schema / catalog snapshot. The snapshot below is what was visible at the last review — execution always re-discovers the roster and ignores any record whose slug is no longer accepted.
- **No provider preference.** Provider identity never appears as a ranking factor. Quality entries cite independent, dated, harness-comparable public evaluations only. Provider or Cursor documentation may establish **price, context size, and availability — never quality**.
- **Expiry is enforced.** Every record expires ≤ 30 days after review, or immediately on a roster / alias / price / benchmark-version / methodology change. An expired record disqualifies its model until refreshed.
- **Uncertainty is first-class.** Qualitative tiers below (leading-cluster / top-quartile / median-band) deliberately avoid false numeric precision; small differences inside one confidence cluster never rank candidates.

## Ledger status

- **Reviewed:** 2026-07-21
- **Expires:** 2026-08-20 (or earlier on any §12.8 trigger)
- **Roster snapshot source:** parent `Task` tool schema, observed 2026-07-21 (snapshot, not canonical)
- **Snapshot slugs:** `claude-fable-5-thinking-high`, `claude-opus-4-8-thinking-high`, `claude-sonnet-5-thinking-high`, `composer-2.5-fast`, `cursor-grok-4.5-high-fast`, `gpt-5.6-sol-medium`, `gpt-5.6-terra-medium`
- **Price source:** [Cursor models & pricing](https://cursor.com/docs/models-and-pricing.md), read 2026-07-21. Prices are per 1M tokens (input / output) and are availability/cost facts only.

## Approved benchmark sources (quality evidence)

Only these source classes may qualify a model, and every citation must be dated:

| Source | Dimension it evidences | Appraisal notes |
| --- | --- | --- |
| [Terminal-Bench 2.1](https://artificialanalysis.ai/evaluations/terminalbench-v2-1) | Terminal / agentic tool use, DevOps-style execution | Independent harness; comparable across models when run by the same evaluator |
| [LiveCodeBench](https://livecodebench.github.io/) | Algorithmic coding, self-repair | Rolling problem set resists contamination; check the date window used |
| [Artificial Analysis](https://artificialanalysis.ai/methodology/intelligence-benchmarking) — task-relevant components | Reasoning, long-context, instruction following, hallucination rate | Use per-dimension components, never the composite headline alone; cap any single evaluator's influence per §12.8 |

## Contamination / exclusion register

| Benchmark family | Status (as of 2026-07-21) | Consequence |
| --- | --- | --- |
| SWE-bench Verified | Retracted Feb 2026 (contamination) | Headline scores never qualify a model |
| SWE-bench Pro | Recommendation retracted Jul 2026 (audit: ~30% broken tasks) | Same exclusion |
| Vendor launch charts / model cards | Self-reported; scaffolding inflates scores 15–30 pts vs neutral harness | Never quality evidence; price/context/availability only |

## Model evidence records

Qualitative capability tiers below are distilled from the 2026-07-21 research pass (independent-evaluator components and dated engineering analyses; vendor claims excluded). Epistemic status is labelled per entry. **A maintainer refreshing this ledger must re-derive each tier from the approved sources above and update the dates — tiers without a fresh source date are expired.**

### `composer-2.5-fast`

- **Aliases:** `composer-2.5` (standard variant via `[fast=false]` / `[]`), `composer`, `composer-latest`
- **Capability profile (established, 2026-07-21):** leading-cluster on fast sustained agentic coding and terminal-driven iteration; top-quartile instruction following on long-running tasks. Not evidenced for frontier-depth architecture reasoning (no leading-cluster reasoning evidence).
- **Context / tools:** standard agentic tool use; no extended-context (1M) claim.
- **Cost (2026-07-21):** standard $0.50 / $2.50; fast variant $3 / $15. First-party pool — exempt from the Teams Cursor Token Rate; favourable included usage. Cost class: **low** (standard), **medium** (fast).
- **Typical fit:** Q1–Q2 implementation, exploration, debugging; escalation source for cheap first attempts.

### `cursor-grok-4.5-high-fast`

- **Aliases:** `grok-4.5` family variants.
- **Capability profile (emerging, 2026-07-21):** top-quartile on long-running coding and knowledge work; sustained-session robustness. Independent per-dimension coverage is thinner than for the Claude/GPT families — treat Q3 qualification as unproven until refreshed evidence lands.
- **Context / tools:** long-running agentic sessions; standard tool use.
- **Cost (2026-07-21):** $2 / $6; first-party pool, Token-Rate exempt, favourable included usage. Cost class: **low-medium**.
- **Typical fit:** Q1–Q2 implementation, exploration, docs; long-session work where cheap sustained context matters.

### `gpt-5.6-terra-medium`

- **Aliases:** `gpt-5.6-terra` (+ fast variant at 2× price).
- **Capability profile (established, 2026-07-21):** top-quartile reasoning and agentic coding (mid-tier of the GPT-5.6 family); solid tool use and instruction following.
- **Context / tools:** standard context; cache writes billed at 1.25× uncached input.
- **Cost (2026-07-21):** $2.50 / $15 (+$0.25/M Cursor Token Rate on Teams). Cost class: **medium**.
- **Typical fit:** Q2 design/implementation/diagnosis; first escalation step from a low-cost model on reasoning-flavoured failures.

### `gpt-5.6-sol-medium`

- **Aliases:** `gpt-5.6-sol` (+ fast variant at 2× price).
- **Capability profile (established, 2026-07-21):** leading-cluster reasoning and agentic capability (top of the GPT-5.6 family); strong on architecture/research synthesis and hard debugging.
- **Context / tools:** long context up to 1M with 2× input pricing beyond the base window (Sol's model page additionally notes 1.5× output beyond 272k — verify on refresh).
- **Cost (2026-07-21):** $5 / $30 (+Token Rate on Teams). Cost class: **high**.
- **Typical fit:** Q3 architecture/review/debugging; Q4 candidate when a second benchmark family corroborates.

### `claude-sonnet-5-thinking-high`

- **Aliases:** `claude-sonnet-5` variants.
- **Capability profile (established, 2026-07-21):** top-quartile-to-leading-cluster agentic coding and review; strong non-hallucination and structured-writing components.
- **Context / tools:** up to 1M extended context at unchanged per-token rates; updated tokenizer can map the same input to **more tokens** — include in cost estimates.
- **Cost (2026-07-21):** $3 / $15 (launch promotion $2 / $10 through 2026-08-31; re-check on refresh) (+Token Rate on Teams). Cost class: **medium**.
- **Typical fit:** Q2–Q3 implementation, review/QA, requirements/docs; long-context work at medium cost.

### `claude-opus-4-8-thinking-high`

- **Aliases:** `claude-opus-4-8`, `claude-opus-4-8-fast`.
- **Capability profile (established, 2026-07-21):** leading-cluster deep reasoning, architecture synthesis, and defect detection; strong long-context fidelity.
- **Context / tools:** up to 1M extended context at unchanged per-token rates.
- **Cost (2026-07-21):** $5 / $25 (+Token Rate on Teams). Cost class: **high**.
- **Typical fit:** Q3 architecture/security/complex debugging; Q4 candidate with corroborating evidence.

### `claude-fable-5-thinking-high`

- **Aliases:** `claude-fable-5` variants.
- **Capability profile (emerging, 2026-07-21):** newest of the snapshot's Claude family; early independent coverage suggests leading-cluster reasoning, but per-dimension independent evidence is thin — under §12.3, thin evidence caps qualification at the tier the evidence actually supports, not the tier the marketing implies.
- **Context / tools:** verify on refresh. Availability note: Cursor docs flag additional privacy/data-retention approval and harm-prevention routing (guardrail trips re-route to Claude Opus) — an availability gate, not a quality fact.
- **Cost (2026-07-21):** about 2× Claude Opus 4.8 (+Token Rate on Teams). Cost class: **premium**.
- **Typical fit:** Q4 candidate only when ≥2 benchmark families corroborate; otherwise rejected on cost with no quality advantage proven.

## Refresh procedure

1. Re-discover the live roster (current `Task` schema / `cursor agent models` / catalog). Prune records for vanished slugs; add stub records (unqualified, "no evidence yet") for new slugs.
2. Re-read the approved benchmark sources; re-derive each capability tier with a fresh date. Anything not re-derived is expired.
3. Re-read the Cursor pricing page; update prices, promotions, and cost classes with the read date.
4. Update the contamination register (new retractions, new exclusions, rehabilitated benchmarks).
5. Bump **Reviewed** / **Expires** in the ledger status.

## Review log

- **2026-07-21** — Initial ledger. Roster from the live parent `Task` schema; prices from the Cursor pricing docs (read same day); capability tiers distilled from the same-day independent research pass; SWE-bench family excluded per the contamination register.
