# Athena Architecture

Athena keeps the live voice path focused and moves slower or riskier work into sidecars and approval flows.

## System Shape

```text
Twilio number
  -> Athena Twilio webhook
  -> Twilio Media Stream
  -> OpenAI Realtime bridge
  -> Athena conversation record
  -> messages, call events, call state
  -> sidecar services
  -> action drafts and approval requests
  -> external action adapters
  -> sidecar event audit trail
```

## Main Concepts

`Conversation`

The durable call or message thread. It links the caller, transcript messages, call events, call state, sidecar events, action drafts, and recordings.

`Message`

A transcript or conversational message. Transcript role normalization lives in `TranscriptRoleNormalizer` so provider labels do not leak through the UI.

`CallEvent`

The telephony and Realtime event log. Twilio status callbacks, media stream lifecycle events, tool calls, Realtime errors, and recording events land here.

`CallState`

The current machine-readable state of the interaction: use case, intent, risk, next step, review status, and compact metadata sidecars can update.

`SidecarEvent`

Append-only audit entries for sidecar observations, state patches, summaries, approval requests, delivery attempts, and failures.

`ActionDraft`

Approval-gated work prepared by Athena or a sidecar. Current adapters include demo SMS, Twilio SMS, and Gemma Mail approval handoff.

## Request Surfaces

Twilio voice:

- `POST /webhooks/twilio/inbound`
- `POST /webhooks/twilio/status`
- `POST /webhooks/twilio/transcription`
- `GET|POST /voice/inbound`
- `GET|POST /voice/outbound`
- `POST /voice/outbound/status`
- `wss://.../ws/twilio-media`

Athena tools:

- `POST /agent_tools/status`
- `POST /agent_tools/lookup`
- `POST /agent_tools/update`
- `POST /agent_tools/web_search`
- `POST /agent_tools/openclaw_chat`
- `POST /agent_tools/athena_calls_latest`
- `POST /agent_tools/athena_call_summary`
- `POST /agent_tools/calendar_availability`
- `POST /agent_tools/gmail_send`
- `POST /agent_tools/command`

Admin and demo:

- `/admin`
- `/admin/demo_scenarios`
- `/admin/conversations`
- `/use-cases`

## Live Call Flow

```text
Twilio inbound webhook
  -> choose local Realtime agent profile
  -> create Conversation, CallEvent, and CallState
  -> return TwiML with Connect Stream
  -> Twilio streams audio to /ws/twilio-media
  -> OpenaiRealtimeTwilioBridge streams audio to OpenAI
  -> OpenAI streams audio back to Twilio
  -> Realtime tool calls go through /agent_tools/command
```

## Sidecar Flow

Twilio completion flow:

```text
status=completed
  -> call state update
  -> AthenaEmailApprovalSidecarService
  -> AthenaTranscriptEmailJob after delay
  -> Gemma Mail approval request
```

Approval flow:

```text
approval event
  -> GemmaMailApprovalJob
  -> Discord message
  -> GemmaMailDiscordApprovalPoller
  -> affirmative reply
  -> gemma-mail-gog send --confirmed
  -> sidecar event
```

## Safety Boundaries

Before production:

- set `ADMIN_USERNAME` and `ADMIN_PASSWORD`
- set `ATHENA_TOOL_SECRET`
- enable `TWILIO_VERIFY_WEBHOOK_SIGNATURES`
- keep Rails bound to `127.0.0.1` when exposed through the AWS reverse tunnel
- require the per-call `stream_token` generated in TwiML before accepting Twilio Media Stream audio
- replace temporary tunnels with a stable deployment URL
- keep PHI out of healthcare demos until legal, security, retention, and vendor review are complete
