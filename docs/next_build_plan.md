# Athena Next Build Plan

Athena is now an OpenAI Realtime-first voice stack. The next build phase should focus on making live demos reliable, useful, and easy to explain.

## Goal

Get to a polished demo loop:

```text
call the number
  -> Athena answers
  -> caller talks through a rev cycle improvement idea
  -> Athena captures a structured idea card
  -> Discord receives the idea report
  -> transcript email is queued when configured
  -> admin UI shows the call, idea, and sidecar trail
```

## Build Order

1. Live call reliability

- Confirm Twilio routes to the active `PUBLIC_BASE_URL`.
- Confirm `OPENAI_API_KEY`, `OPENAI_REALTIME_MODEL`, and `OPENAI_REALTIME_VOICE`.
- Keep `script/smoke_twilio_voice` green.
- Review the last call from `/admin/conversations` after every live test.

2. Idea capture confidence

- Keep `athena_command` small and predictable.
- Prefer `semantic_request` for natural language asks.
- Make `capture_idea` the primary live-demo tool path.
- Confirm each live call produces one useful `IdeaCapture`.
- Confirm the Athena Discord channel receives the report.
- Keep web search replies grounded in returned snippets.
- Log arguments and compact results into `CallEvent`.

3. Email approval polish

- Use `ATHENA_APPROVAL_CHANNEL` and `ATHENA_APPROVAL_TARGET` for the dedicated Athena approval destination.
- Keep approval IDs stable and visible.
- Make edit/approve/cancel replies work in the same Discord channel.
- Keep transcript emails separate from user-requested emails by using suffixed approval IDs.

4. Admin demo polish

- Conversations should show status, transcript, metadata, timeline, queued actions, and recording state.
- The timeline should make tool calls, approval requests, and sends easy to narrate.
- Demo scenarios should seed realistic records without sending real external messages.

5. Use-case expansion

- Rev cycle ideation session.
- Automation opportunity discovery.
- Denials and cost savings lab.
- Retreat review library with search, tags, and exports.

## Near-Term Backlog

- Add a visible Realtime health panel to the dashboard.
- Add a last-call diagnostic button that summarizes tool calls and failures.
- Add filters and tags to the Ideas page.
- Add CSV/export support for retreat prep.
- Add a one-command demo reset for conversations, sidecar events, and action drafts.
- Add a clear status indicator for Discord approval polling.
- Add operator notes and tags to conversations.
- Add a stricter policy layer for healthcare demo scenarios.

## Done Definition

A slice is demo-ready when:

- a call can be placed to the Twilio number
- Athena answers with the configured profile
- `capture_idea` succeeds
- admin transcript roles are correct
- the idea report reaches Discord
- the Ideas admin page shows the captured card
- the conversation timeline tells the story without needing logs
