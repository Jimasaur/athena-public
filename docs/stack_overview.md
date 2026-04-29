# Athena Stack Overview

Athena is a voice-assistant operations stack for turning revenue cycle retreat calls into structured, reviewable improvement ideas.

At a high level, Athena answers this question:

> What if a rough improvement idea spoken into a phone could become a durable workshop-ready insight?

## Core Idea

Someone calls a real Twilio number, talks to Athena, and Athena captures the call as state, transcript messages, tool calls, sidecar events, idea cards, Discord reports, and follow-up work.

Athena is now built around one live voice path:

```text
Caller
  -> Twilio phone number
  -> Athena Rails app
  -> OpenAI Realtime bridge
  -> Athena data model
  -> sidecar services
  -> IdeaCapture record
  -> Discord report and admin review
```

## Main Layers

Twilio is the phone layer. It owns the phone number, call routing, media stream, call status callbacks, optional transcription callbacks, SMS readiness, and telephony plumbing.

OpenAI Realtime is the live voice layer. Athena speaks with the caller, listens over the Twilio media stream, calls Athena tools, and can adapt while the call is still happening.

Athena is the operating layer. It stores the call, normalizes transcripts, tracks call state, exposes tools to Athena, displays the admin UI, and turns conversations into idea cards.

Sidecars are intelligence helpers. They can observe, summarize, search, classify, draft actions, or hand work to specialized local agents without making the live call flow heavy.

OpenClaw can handle sidecar delivery into Discord. Gemma Mail remains available for approval-gated email workflows, but the main Athena path is idea capture and retreat reporting.

## Typical Demo Flow

```text
1. Call the Athena/Twilio number.
2. Athena answers through OpenAI Realtime.
3. Caller shares a revenue cycle automation, innovation, cost savings, or workflow idea.
4. Athena calls `athena_command` with `capture_idea`.
5. Athena records the tool call and creates an `IdeaCapture`.
6. A sidecar posts the idea to Discord for testing.
7. The admin UI shows the call, transcript, state, idea, and sidecar events.
8. Any external side effects stay approval-gated.
```

## Current Capabilities

- Answer a live call through Twilio and OpenAI Realtime.
- Store conversations, call events, transcript messages, and recordings.
- Normalize transcript roles so caller and assistant labels stay correct.
- Let Athena call Athena tools for idea capture, status, lookup, search, summaries, contacts, and email handoff.
- Use Brave Search for current information and weather snippets.
- Store `IdeaCapture` records for retreat review.
- Report captured ideas to the Athena Discord channel.
- Draft follow-up work after a call.
- Send email approval requests to Discord through Gemma Mail/OpenClaw.
- Email call transcripts after calls.
- Provide admin pages for demo scenarios, use-case exploration, idea review, and conversation review.

## Product Directions

Athena currently uses four retreat-oriented lenses on the same Twilio plus OpenAI Realtime foundation:

- Rev cycle ideation session.
- Automation opportunity discovery.
- Denials and cost savings lab.
- Retreat review library.

The point is not four separate products forever. The lenses help stress-test architecture, user experience, compliance boundaries, and operator value around the retreat workflow.

## Safety Posture

Athena is an exploration and demo stack, not a production healthcare system.

Before production use, it needs stable hosting, secrets hardening, webhook verification, vendor review, privacy review, retention rules, compliance review, and careful handling of PHI/PII.
