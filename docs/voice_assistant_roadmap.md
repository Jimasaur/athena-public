# Voice Assistant Roadmap

Athena's live assistant strategy is OpenAI Realtime only.

## Current Foundation

- Twilio receives and routes calls.
- Athena creates the conversation, call events, call state, and TwiML.
- Twilio Media Streams connect to `/ws/twilio-media`.
- `OpenaiRealtimeTwilioBridge` streams audio to and from OpenAI Realtime.
- Athena can call `athena_command` for tools and sidecars.
- Athena stores transcripts, tool calls, status callbacks, and recordings.

## Phase 1: Demo Reliability

- Keep the Realtime path stable on local tunnels.
- Make first-message behavior predictable.
- Keep transcript role labels correct.
- Make failed tool calls visible in the admin timeline.
- Keep email approval requests reliable in the dedicated Athena Discord channel.

## Phase 2: Sidecar Intelligence

- Add compact state patches from classifiers and summarizers.
- Add next-best-question suggestions.
- Add risk and escalation signals.
- Add a live operator status panel.
- Add a last-call diagnostic view.

## Phase 3: Product Workflows

- Personal command workflows.
- Small business intake and follow-up.
- Healthcare operational pilots with synthetic or non-PHI data.
- Approval-gated email, SMS, calendar, and ticketing actions.

## Phase 4: Hardening

- Stable deployment URL.
- Twilio signature verification.
- Strong admin auth.
- Tool secret rotation.
- Retention and deletion rules.
- Privacy and compliance review before sensitive deployments.
