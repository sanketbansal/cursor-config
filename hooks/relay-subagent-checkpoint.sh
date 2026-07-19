#!/usr/bin/env python3
"""subagentStop hook — relay `cursor-checkpoint` marker to the parent agent.

Reads the `subagentStop` JSON event on stdin. If the subagent's output
contains a fenced code block whose info-string is `cursor-checkpoint`,
parses the embedded YAML schema (defined in
`~/.cursor/skills/subagent-orchestration/SKILL.md`) and emits a
`followup_message` instructing the parent agent to call `AskQuestion`
verbatim and then resume the subagent with the user's answer.

If no marker is found, or any parsing step fails, emits an empty JSON
object and exits 0 (fail open). This is by design — the hook is a
defence-in-depth layer over the User Rules instruction. The parent is
required to relay regardless of hook state; the hook only makes
ignoring the requirement harder.

Roster-agnostic: there is no per-subagent name list anywhere in this
script. The presence of the `cursor-checkpoint` block is the trigger.
Any subagent (current or future) that emits the marker gets relayed.
Any subagent that does not emit it (Cursor built-ins like `explore`,
`shell`, `browser-use`, or stateless future agents) makes this script
a no-op.
"""

from __future__ import annotations

import json
import re
import sys
import textwrap


def _emit(obj: dict) -> None:
    """Write a JSON object to stdout and exit 0."""
    json.dump(obj, sys.stdout)
    sys.exit(0)


def _read_event() -> dict | None:
    try:
        return json.load(sys.stdin)
    except Exception:
        return None


_OUTPUT_KEYS = (
    "subagent_output",
    "output",
    "agent_output",
    "result",
    "message",
    "text",
    "content",
)

_AGENT_ID_KEYS = ("subagent_id", "agent_id", "id", "task_id")
_AGENT_TYPE_KEYS = ("subagent_type", "agent_type", "type", "name")


def _walk_for_string(event: object, candidate_keys: tuple[str, ...]) -> str:
    """Return the first non-empty string value found at the top level or under
    a `subagent` / `agent` / `task` nested object, for any of the candidate keys.
    Defensive against the exact field-name shape `subagentStop` ships with."""
    if not isinstance(event, dict):
        return ""
    for key in candidate_keys:
        v = event.get(key)
        if isinstance(v, str) and v:
            return v
    for nested in ("subagent", "agent", "task"):
        sub = event.get(nested)
        if isinstance(sub, dict):
            for key in candidate_keys:
                v = sub.get(key)
                if isinstance(v, str) and v:
                    return v
    return ""


def _extract_output_text(event: object) -> str:
    text = _walk_for_string(event, _OUTPUT_KEYS)
    if text:
        return text
    try:
        return json.dumps(event)
    except Exception:
        return str(event)


_BLOCK_RE = re.compile(
    r"^[ \t]*```[ \t]*cursor-checkpoint\b[^\n]*\n(.*?)\n[ \t]*```",
    re.DOTALL | re.MULTILINE,
)


def _extract_block_body(text: str) -> str | None:
    m = _BLOCK_RE.search(text or "")
    return m.group(1) if m else None


def _safe_parse_yaml(body: str) -> object:
    try:
        import yaml
    except Exception:
        return None
    try:
        return yaml.safe_load(body)
    except Exception:
        return None


def _format_options(options: object) -> str:
    if not isinstance(options, list):
        return ""
    lines: list[str] = []
    for opt in options:
        if not isinstance(opt, dict):
            continue
        oid = opt.get("id", "")
        label = opt.get("label", "")
        tradeoff = opt.get("tradeoff", "")
        line = f"  - id={oid!r} label={label!r}"
        if tradeoff:
            line += f" tradeoff={tradeoff!r}"
        lines.append(line)
    return "\n".join(lines)


def _build_followup(agent_type_hint: str, agent_id_hint: str, parsed: object) -> str | None:
    if not isinstance(parsed, dict):
        return None
    agent = parsed.get("agent") or agent_type_hint or "unknown"
    checkpoint = parsed.get("checkpoint") or "?"
    kind = parsed.get("kind") if isinstance(parsed.get("kind"), str) else "question"
    question = parsed.get("question")
    options = parsed.get("options")
    default = parsed.get("default")
    if not isinstance(question, str) or not question.strip():
        return None
    options_block = _format_options(options) or "  (no options provided)"
    default_str = default if isinstance(default, (str, int)) else "(none)"
    block_description = (
        "reported an execution blocker (`kind: blocked` — its retry budget "
        "is exhausted; the options are recovery paths)"
        if kind == "blocked"
        else "returned a `cursor-checkpoint` block"
    )
    return (
        f"STOP. Subagent `{agent}` (id `{agent_id_hint or 'unknown'}`, "
        f"checkpoint `{checkpoint}`) {block_description}.\n\n"
        "You MUST relay this question to the user via the `AskQuestion` tool "
        "BEFORE any other tool call. Do not assume an answer, paraphrase the "
        "question, or take any other action until the user has responded.\n\n"
        "QUESTION (verbatim):\n"
        f"{textwrap.indent(question.rstrip(), '  ')}\n\n"
        "OPTIONS (use these as AskQuestion options, with each `id` as the "
        "option id and the `label` as the option label; surface the `tradeoff` "
        "to the user inline):\n"
        f"{options_block}\n\n"
        f"RECOMMENDED DEFAULT (do NOT skip the AskQuestion call): {default_str}\n\n"
        "After the user answers, resume this same subagent with "
        f"`Task(subagent_type=\"{agent}\", resume=\"{agent_id_hint}\", "
        "prompt=<user's answer prepended to a brief continue-instruction>)`. "
        "Never start a fresh subagent of the same type for the same task — "
        "`resume` preserves the subagent's draft and prior checkpoint history.\n\n"
        "This relay rule is governed by "
        "`~/.cursor/skills/subagent-orchestration/SKILL.md` (§6 Relay "
        "protocol) and the User Rules \"Subagent orchestration (always "
        "apply)\" section."
    )


def main() -> None:
    event = _read_event()
    output = _extract_output_text(event)
    body = _extract_block_body(output)
    if not body:
        _emit({})
        return
    parsed = _safe_parse_yaml(body)
    msg = _build_followup(
        _walk_for_string(event, _AGENT_TYPE_KEYS),
        _walk_for_string(event, _AGENT_ID_KEYS),
        parsed,
    )
    if msg is None:
        _emit({})
        return
    _emit({"followup_message": msg})


if __name__ == "__main__":
    try:
        main()
    except Exception:
        _emit({})
