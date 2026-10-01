# Athena

Athena is a Rails control plane for OpenAI Realtime voice agents. Twilio brings calls in, OpenAI Realtime runs the live speech loop, and Athena keeps the durable record: transcripts, tool calls, sidecar state, approvals, and follow-up actions.

## Project status

Public development prototype and reference implementation. The repository demonstrates an integration architecture; it is not a production-readiness, security, or compliance certification. Use synthetic data for evaluation, and review authentication, permissions, retention, provider costs, and approval behavior before enabling live calls or external actions.

## What to explore

- **Integration design:** a Twilio call becomes a streaming OpenAI Realtime session with a shared tool dispatcher.
- **Operational visibility:** Rails models and admin views retain conversations, tool activity, and action drafts.
- **Human review:** sidecar and email-handoff workflows separate proposed actions from approval.
- **Demo walkthrough:** start with [the adoption guide](docs/adoption_guide.md) and [demo scenarios](docs/demo_walkthrough.md).

## Fast Path

For a safe local tour that does not send live SMS or email:

```bash
cp .env.example .env
bin/setup --skip-server
bin/doctor
script/seed_demo_scenarios
bin/dev
```

Then open:

- `http://127.0.0.1:3000/admin`
- `http://127.0.0.1:3000/admin/demo_scenarios`
- `http://127.0.0.1:3000/use-cases`

To use port 3001:

```bash
PORT=3001 bin/dev
```

## Live Voice Path

Athena now standardizes on OpenAI Realtime for live calls:

```text
Twilio number
  -> Athena /voice/inbound
  -> Twilio Media Stream /ws/twilio-media
  -> OpenAI Realtime
  -> Athena tool dispatcher /agent_tools/command
  -> sidecars, approvals, summaries, email handoff, search
```

Configure your Twilio number:

- Voice webhook: `POST https://YOUR_BASE_URL/voice/inbound`
- Status callback: `POST https://YOUR_BASE_URL/voice/outbound/status`

Athena returns TwiML with:

- `<Connect><Stream>` to `wss://YOUR_BASE_URL/ws/twilio-media`

OpenAI Realtime is the primary transcript source. Twilio transcription can be enabled as an optional diagnostic mirror with `OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED=true`.

## Configuration

Copy `.env.example` to `.env` for local exploration, or enter values in `/admin/app_settings`. Database-backed `AppSetting` values take precedence over environment values.

Minimum live voice configuration:

```bash
OPENAI_API_KEY=your_openai_key
OPENAI_REALTIME_MODEL=gpt-realtime-1.5
OPENAI_REALTIME_VOICE=marin
OPENAI_REALTIME_INTERRUPT_RESPONSE=false
TWILIO_ACCOUNT_SID=your_twilio_account_sid
TWILIO_AUTH_TOKEN=your_twilio_auth_token
PUBLIC_BASE_URL=https://YOUR_PUBLIC_BASE_URL
ATHENA_INTERNAL_BASE_URL=http://127.0.0.1:3001
```

OpenAI Realtime voice, transcription, noise reduction, turn detection, and advanced session overrides are available in `/admin/app_settings`.

Useful tool and sidecar configuration:

```bash
ATHENA_TOOL_SECRET=shared_tool_secret
BRAVE_SEARCH_API_KEY=your_brave_search_key
OPENCLAW_CLI=openclaw
OPENCLAW_PROFILE=default
OPENCLAW_AGENT=main
GEMMA_MAIL_OPENCLAW_PROFILE=gemma4
GEMMA_MAIL_OPENCLAW_AGENT=mail
GEMMA_MAIL_APPROVAL_CHANNEL=discord
GEMMA_MAIL_APPROVAL_TARGET=channel:YOUR_GEMMA_MAIL_CHANNEL_ID
ATHENA_IDEAS_DISCORD_TARGET=channel:YOUR_DISCORD_CHANNEL_ID
ATHENA_IDEAS_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
GOOGLE_CALENDAR_TOOL_URL=https://your-calendar-connector.example.com
GMAIL_TOOL_URL=https://your-gmail-connector.example.com
```

## Realtime Profiles

The admin Agents page manages local OpenAI Realtime profiles. A profile controls:

- Twilio number mapping
- system prompt
- opening greeting
- Realtime voice override
- local notes for Athena tools

Twilio routing always uses the OpenAI Realtime bridge. Legacy provider override params are ignored.

## Tool Surface

OpenAI Realtime receives one Athena tool, `athena_command`, which dispatches to:

- status checks
- web search and weather through Brave Search snippets
- rev cycle idea capture and Discord reporting
- contact lookup
- recent-call summaries
- OpenClaw sidecar prompts
- approval-gated Gemma Mail email handoff

External side effects should stay approval-gated. Athena can request an email, Gemma Mail posts the approval in Discord, and the email sends only after an affirmative Discord reply.

## Docs Map

- `docs/adoption_guide.md` - start here when exploring Athena cold.
- `docs/stack_overview.md` - super high-level map of what the stack is and why it exists.
- `docs/architecture.md` - system map, main objects, request surfaces, and sidecar flow.
- `docs/openai_realtime_provider.md` - OpenAI Realtime bridge notes.
- `docs/demo_walkthrough.md` - scripted demo path.
- `docs/subdomain_handoff.md` - what the web/DNS engineer needs for `athena.example.com`.
- `docs/testing_sidecar_flow.md` - local smoke tests and live sidecar testing.
- `docs/next_build_plan.md` - current roadmap and sequencing.
- `docs/project_stubs/README.md` - early project/use-case notes inherited from the broader voice-ops exploration.

## Tests

```bash
bin/rails test
bin/rails test:system
bin/ci
```

Safe smoke suite:

```bash
script/smoke_athena_all
```

Local readiness check:

```bash
bin/doctor
```

## Notes

- Admin UI uses HTTP basic auth when configured. In `ATHENA_PUBLIC_DEMO_MODE` or production, missing admin/tool secrets fail closed.
- Data is stored in SQLite for development.
- Live voice calls use Twilio Media Streams plus OpenAI Realtime.
