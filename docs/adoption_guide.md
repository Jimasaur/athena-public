# Athena Adoption Guide

This guide is for the next person opening Athena cold. It gets them from clone to a useful demo without needing to understand every sidecar first.

## What Athena Is

Athena is the control plane around an OpenAI Realtime phone assistant:

```text
phone call -> OpenAI Realtime voice -> Athena records -> idea capture -> Discord report -> review library
```

The live assistant is Athena. Athena stores the call, transcript, call state, timeline, idea cards, action drafts, approvals, and external side effects.

## Fifteen-Minute Local Tour

```sh
cp .env.example .env
bin/setup --skip-server
bin/doctor
script/seed_demo_scenarios
bin/dev
```

Then open:

```text
http://127.0.0.1:3000/admin
http://127.0.0.1:3000/admin/demo_scenarios
http://127.0.0.1:3000/use-cases
```

If you prefer port 3001:

```sh
PORT=3001 bin/dev
```

## Demo Without External Sends

Run the local smoke suite:

```sh
script/smoke_athena_all
```

Seed scenario conversations:

```sh
script/seed_demo_scenarios
```

Seeded conversations include transcripts, call states, sidecar events, idea cards, and action drafts. Demo-marked actions write dry-run audit events instead of sending live SMS.

## Live Demo Readiness

For a real phone-call demo, configure these first:

- `PUBLIC_BASE_URL`
- `OPENAI_API_KEY`
- `OPENAI_REALTIME_MODEL`
- `OPENAI_REALTIME_VOICE`
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- one `AgentSetting` with a real `twilio_number`
- `ATHENA_APPROVAL_TARGET` for Discord approvals
- `GEMMA_MAIL_GMAIL_ACCOUNT` for approved email sends

Then check:

```sh
bin/doctor
script/smoke_twilio_voice
```

Live SMS should stay paused until the 10DLC campaign and Messaging Service are approved and attached. When that is ready, set:

```sh
TWILIO_MESSAGING_SERVICE_SID=MGXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

## Where To Look First

- `README.md`: setup, tool endpoints, and core configuration.
- `docs/stack_overview.md`: high-level map.
- `docs/architecture.md`: system map and major objects.
- `docs/openai_realtime_provider.md`: Realtime bridge details.
- `docs/demo_walkthrough.md`: stakeholder demo flow.
- `docs/testing_sidecar_flow.md`: smoke scripts and sidecar testing.
- `docs/next_build_plan.md`: current roadmap and sequencing.
- `docs/project_stubs/README.md`: early project/use-case notes inherited from the broader voice-ops exploration.
- `app/models/use_case_catalog.rb`: use-case page content and user stories.
- `app/models/idea_capture.rb`: structured retreat idea records.
- `app/services/*sidecar*`: post-call and approval sidecar logic.
- `app/controllers/agent_tools_controller.rb`: tool surface Athena can call.

## Operating Defaults

- draft before send
- human approval before external side effects
- demo mode before live SMS
- compact sidecar patches
- no PHI in healthcare demos
- admin auth enabled before public deployment
- Twilio signature verification enabled once `PUBLIC_BASE_URL` is stable
