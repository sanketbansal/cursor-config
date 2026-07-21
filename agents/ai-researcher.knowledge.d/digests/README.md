# Research digests — pending inbox (not the durable KB)

This directory is the **inbox** for the weekly "Weekly AI research digest" Cursor Automation. Each run commits one dated file behind a PR on the `cursor-config` repo; merging the PR is the human approval gate for the digest landing here.

## Layout

- `YYYY-MM-DD.md` — one dated digest per automation run: paper / blog titles, URLs, publication dates, 1–2 line relevance notes, and an evidence-tier hint per item (peer-reviewed / preprint / model card / engineering blog).
- `PENDING-REVIEW.md` — pointer to digests not yet processed by `ai-researcher` into durable-KB proposals. Rewritten by the automation each run; entries are removed when a digest has been promoted or explicitly dismissed.
- `README.md` — this file.

## Inbox vs durable KB

Digests are **raw, dated, perishable intake** — they are never the durable knowledge base:

- The durable KB is the append-only section above `<!-- AI-RESEARCHER-KB:EXTEND-HERE -->` in `agents/ai-researcher.md` (plus topic sidecar fragments in `agents/ai-researcher.knowledge.d/`). It holds distilled, slow-aging patterns only.
- Promotion from digest → durable KB happens **only** through `ai-researcher`'s relay-gated KB checkpoint (see `agents/ai-researcher.md` §Knowledge base & self-update). The automation must never edit the durable KB section or the sidecar topic fragments directly.
- Perishable facts (model rankings, prices, leaderboard positions) stay in digests and expire there; they are re-retrieved live per research invocation.

## How digests reach the local IDE

Automation PR merged into `main` → `/Users/Shared/cursor-config` pulls it (login LaunchAgent runs `git pull --ff-only`, or manually `git pull && bash bootstrap.sh`) → `bootstrap.sh` copies this directory into `~/.cursor/agents/ai-researcher.knowledge.d/digests/` → `ai-researcher` reads it at session start as its pending inbox.
