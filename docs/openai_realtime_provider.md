# OpenAI Realtime Voice Path

Athena routes the live Twilio voice path to OpenAI Realtime.

Twilio and Athena are the durable operating layer, while OpenAI Realtime owns the live speech loop:

```text
Twilio number
  -> Athena /voice/inbound
  -> Twilio <Connect><Stream>
  -> Athena /ws/twilio-media
  -> OpenAI Realtime WebSocket
  -> Athena tool dispatcher when the model calls athena_command
```

## Required Config

Set:

```sh
OPENAI_API_KEY=sk-...
OPENAI_REALTIME_MODEL=gpt-realtime-1.5
OPENAI_REALTIME_VOICE=marin
OPENAI_REALTIME_TRANSCRIPTION_MODEL=gpt-4o-mini-transcribe
OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED=false
```

Then restart Athena.

The admin Config page exposes the supported Realtime session controls:

```sh
OPENAI_REALTIME_INPUT_NOISE_REDUCTION=near_field
OPENAI_REALTIME_TURN_DETECTION_TYPE=server_vad
OPENAI_REALTIME_VAD_THRESHOLD=0.65
OPENAI_REALTIME_VAD_PREFIX_PADDING_MS=300
OPENAI_REALTIME_VAD_SILENCE_DURATION_MS=500
OPENAI_REALTIME_VAD_IDLE_TIMEOUT_MS=6000
OPENAI_REALTIME_SEMANTIC_EAGERNESS=auto
OPENAI_REALTIME_CREATE_RESPONSE=true
OPENAI_REALTIME_INTERRUPT_RESPONSE=false
OPENAI_REALTIME_INTERRUPT_GRACE_MS=2500
OPENAI_REALTIME_SESSION_OVERRIDES_JSON=
```

`OPENAI_REALTIME_SESSION_OVERRIDES_JSON` can merge advanced OpenAI session fields into the generated `session.update` payload.

`OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED` is disabled by default because OpenAI Realtime already produces call transcripts. Turn it on only when you intentionally want a second Twilio transcript mirror for comparison or diagnostics.

For local tool callbacks, Athena uses:

```sh
ATHENA_INTERNAL_BASE_URL=http://127.0.0.1:3001
```

If that is blank, it falls back to `PUBLIC_BASE_URL`.

## Flow

```text
Twilio -> Athena -> Twilio Media Stream -> OpenAI Realtime
```

The OpenAI path uses bidirectional Twilio streaming. Athena sends Twilio's G.711 mu-law audio frames directly to Realtime, asks Realtime to return G.711 mu-law audio, and forwards those audio deltas back to Twilio.

## Tool Calling

The Realtime session exposes one function tool:

```text
athena_command
```

That tool calls Athena's existing dispatcher:

```text
POST /agent_tools/command
```

So OpenAI Realtime can use the same Athena capabilities Athena already uses:

- status checks
- web search and weather through Brave Search snippets
- contact lookup
- call summaries
- approval-gated email handoff

## Current Limitations

This is a demo-ready provider switch, not yet a hardened production bridge.

Known next hardening items:

- richer interruption handling
- more detailed Realtime event audit views
- stronger reconnect behavior
- deeper tool result shaping
- deeper prompt/profile editing in the admin UI
- healthcare-specific compliance review before PHI use
