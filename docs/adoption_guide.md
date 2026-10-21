# Athena Adoption Guide

This guide is for the next person opening Athena cold. It gets them from clone to a useful demo without needing to understand every sidecar first.

## What Athena Is

Athena is a workspace for turning conversations and incoming requests into coordinated operational work:

```text
voice idea or staff web request -> work item -> owner and next step -> reviewed handoff -> recorded outcome
```

Athena keeps source conversations and ideas alongside work items, operator decisions, and delivery history. Delivery acknowledgement and work resolution are tracked separately.

## Fifteen-Minute Local Tour

Use Ruby 3.4.7 and Bundler 4.0.2 with a POSIX shell (Linux, macOS, or WSL). See [operations](operations.md) for native dependencies and configuration behavior.

```sh
cp .env.example .env
bin/setup --skip-server
bin/doctor
script/seed_work_queue_demo
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

The example `.env` defaults to port 3000. Leave `PUBLIC_BASE_URL` blank for the local tour; setting a public origin intentionally requires admin authentication. Keep provider credentials blank until you move to a live evaluation.

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

From **Ideas**, search across the card content, filter by category or status, inspect the source conversation, and mark a card reviewed or archived. CSV export includes all matching ideas, across pages. Reopen a card when it needs more work. These review changes create timeline events without executing external actions.

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
