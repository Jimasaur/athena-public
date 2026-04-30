# Athena Sidecar Contract

Sidecars make Athena smarter without overloading the live call loop.

## Contract Shape

Sidecars read durable Athena objects, create audit events, and optionally prepare approval-gated actions.

```text
Conversation
  -> Messages
  -> CallState
  -> SidecarEvent
  -> ActionDraft
```

## Call State Example

```json
{
  "schema": "call_state.v1",
  "call_id": "CA...",
  "conversation_id": 123,
  "space": "healthcare",
  "use_case_slug": "rev-cycle-ideation-session",
  "provider": "openai_realtime",
  "status": "active",
  "caller": {
    "name": "Unknown caller",
    "phone": "+14155552001",
    "known_contact": true
  },
  "intent": {
    "label": "rev_cycle_ideation",
    "confidence": 0.82
  },
  "risk": {
    "level": "low",
    "reasons": []
  },
  "active_constraints": [
    "draft_only_external_actions",
    "voice_responses_short"
  ],
  "allowed_actions": [
    "lookup",
    "summarize",
    "draft",
    "capture_idea"
  ],
  "handoff_required": false,
  "next_best_question": null,
  "facts": [],
  "review_status": "pending"
}
```

## Sidecar Event Example

```json
{
  "source": "athena_transcript_email_sidecar",
  "kind": "transcript_email.queued",
  "provider": "athena",
  "payload": {
    "ok": true,
    "approval_id": "athena-conversation-123-transcript",
    "recipient": "jordan@example.com",
    "subject": "Athena call transcript"
  },
  "evidence": {
    "conversation_id": 123,
    "message_ids": [1, 2, 3]
  },
  "changes_call_behavior": false,
  "requires_review": true
}
```

## Action Draft Example

```json
{
  "kind": "email",
  "status": "pending_approval",
  "created_by": "agent_tool",
  "approval_required": true,
  "recipient": {
    "email": "jordan@example.com"
  },
  "content": {
    "subject": "Follow-up",
    "body": "Thanks for the call."
  },
  "external_side_effect": {
    "type": "send_email",
    "executed": false
  }
}
```

## Sidecar Rules

- Record what happened before changing state.
- Keep payloads compact and structured.
- Mark external side effects as approval-gated by default.
- Use `provider: "athena"` for internal sidecar actions unless a real external adapter performed the work.
- Prefer appending `SidecarEvent` records over mutating old evidence.
- Never put secrets in payloads, evidence, transcripts, or logs.

## Common Sidecars

- transcript email sidecar
- email approval sidecar
- idea capture sidecar
- idea Discord reporter
- Discord approval poller
- call summarizer
- follow-up drafter
- web search responder
- future calendar, CRM, EHR, ticketing, and policy-checking adapters
