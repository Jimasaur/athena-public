# Athena Project Notes

Athena started from a broader voice-ops exploration, but this repo is now focused on one separate instance: a revenue cycle retreat ideation line.

Each workflow uses the same voice track:

- Twilio phone number
- OpenAI Realtime bridge
- Athena call state
- sidecar observers
- `IdeaCapture` records
- Discord reports for testing
- admin review library

## Current Workflow List

1. Rev Cycle Ideation Session
2. Automation Opportunity Discovery
3. Denials and Cost Savings Lab
4. Retreat Review Library

## Runtime Assumptions

- Athena is the source of truth for contacts, conversations, call events, transcript records, idea cards, summaries, and operator review.
- Local sidecar services may assist with LLM, search, scoring, summarization, and workflow intelligence.
- External actions start as draft-only or approval-gated.
- Healthcare demos use synthetic or non-PHI workflows until security, BAAs, audit, retention, consent, and access controls are in place.

## OpenAI Realtime Track

Primary pattern:

- Twilio Media Streams connect to the local OpenAI Realtime bridge.
- The bridge streams caller audio to the Realtime API over WebSocket.
- The bridge streams model audio deltas back to Twilio.
- Athena exposes a compact `athena_command` tool.
- The main live-demo command is `capture_idea`.

Useful OpenAI references:

- Realtime API: https://developers.openai.com/api/docs/guides/realtime
- Realtime conversations: https://developers.openai.com/api/docs/guides/realtime-conversations
- Realtime MCP: https://developers.openai.com/api/docs/guides/realtime-mcp
- OpenAI Docs MCP for builder-side documentation lookup: https://developers.openai.com/learn/docs-mcp
