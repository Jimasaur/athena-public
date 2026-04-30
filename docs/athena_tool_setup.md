# Athena Tool Setup

Athena calls Athena tools through the OpenAI Realtime bridge. The bridge exposes one compact Realtime function named `athena_command`, then Athena dispatches to the right local tool.

## Realtime Function

```json
{
  "type": "function",
  "name": "athena_command",
  "description": "Call Athena for status, web search, weather, contact lookup, call summaries, or approval-gated email handoff.",
  "parameters": {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "enum": [
          "semantic_request",
          "status",
          "web_search",
          "find_contact",
          "summarize_last_call",
          "email"
        ]
      },
      "request": {
        "type": "string"
      }
    },
    "required": ["command", "request"],
    "additionalProperties": false
  }
}
```

## Dispatcher Endpoint

```text
POST /agent_tools/command
```

The bridge sends:

```json
{
  "command": "semantic_request",
  "request": "Email the retreat coordinator a quick recap of this call.",
  "conversation_id": 123,
  "call_sid": "CA..."
}
```

## Tool Secret

Use `ATHENA_TOOL_SECRET` to protect internal tool calls when the app is reachable outside the local machine.

Header:

```text
X-Athena-Tool-Secret: <secret>
```

## Voice Behavior Rules

Athena should:

- keep spoken answers short
- use Athena for current information, weather, summaries, contacts, and email handoff
- never claim an email was sent until the approval flow reports it was sent
- ground current answers in returned tool results
- avoid mentioning internal JSON, sidecars, webhooks, or implementation details to the caller
