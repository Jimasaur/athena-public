# Athena

Athena is a workspace for turning conversations and incoming requests into reviewed operational work. Capture the request, preserve its context, assign the next step, and keep decisions and handoffs visible.

**Turn conversations into work your team can finish.** Work items hold ownership, status, priority, due dates, and resolution notes. Voice idea capture and staff web intake feed the same queue. The Rails/Twilio/OpenAI Realtime stack retains the source conversations; reviewed webhook handoffs connect work to a downstream system.

## Project status

Public development prototype and reference implementation. The repository demonstrates an integration architecture; it is not a production-readiness, security, or compliance certification. Use synthetic data for evaluation, and review authentication, permissions, retention, provider costs, and approval behavior before enabling live calls or external actions.

## What to explore

- **Work intake:** staff create requests through an authenticated web form; voice idea capture creates conversation-linked work items.
- **Coordination:** filter the work queue, assign owners and dates, record progress, and resolve work with a note.
- **Reviewed handoffs:** prepare a payload, approve its exact saved revision, and record delivery separately from resolution.
- **Source context:** conversations, transcripts, ideas, tool activity, and event history remain available.
- **Demo walkthrough:** start with [the adoption guide](docs/adoption_guide.md) and [demo scenarios](docs/demo_walkthrough.md).

## Fast Path

Prerequisites: Ruby **3.4.7**, Bundler **4.0.2**, Git, and SQLite development libraries/native build tools if your platform needs to compile gems. `bin/dev` and the smoke scripts use a POSIX shell; use Linux, macOS, or WSL for the documented shell workflow. Node.js is not required for this importmap/Tailwind Rails app.

Clone the public reference repository, then prepare a local tour:

```bash
git clone https://github.com/Jimasaur/athena-public.git
cd athena-public
cp .env.example .env
bin/setup --skip-server
bin/doctor
script/seed_work_queue_demo
bin/dev
```

Then open:

- `http://127.0.0.1:3000/admin` - work queue
- `http://127.0.0.1:3000/admin/demo_scenarios`
- `http://127.0.0.1:3000/use-cases`

The example uses port **3000** and leaves `PUBLIC_BASE_URL` blank so the local console can open without public deployment credentials. `bin/dev` loads `.env`; the Rails console and standalone scripts use their process environment and database settings. To use another port:

```bash
PORT=3001 bin/dev
```

Seeded scenario actions are dry runs. Keep provider credentials blank for the initial tour and use synthetic data. The readiness panels describe configuration, not live provider health.

Development binds to `127.0.0.1`. `bin/dev` starts the web and CSS processes; start `script/watch_gemma_mail_approvals` separately only when intentionally evaluating configured live approvals.

## Review an idea

1. Open **Demos** and launch a synthetic scenario.
2. Open **Ideas**, search the captured content, and filter by category or review status.
3. Inspect the source conversation, mark the idea reviewed, archive it, or reopen it.
4. Export the matching library as CSV for workshop preparation. Exports include impact hypotheses and source conversation IDs; spreadsheet formula prefixes are escaped.

Review and archive actions are recorded in the conversation timeline. They do not execute follow-up drafts or contact external services.

## From intake to follow-through

1. Open **Work queue**, then **New work item**, to capture a staff request. Web intake starts in **Needs review** and does not call a model or send a message.
2. Assign an owner, priority, and due date. Keep the description and next step editable; concurrent edits are checked with a saved revision.
3. Prepare a handoff, inspect its saved payload, approve it, then explicitly deliver it. Synthetic records always simulate delivery. Live handoff is disabled until configured.
4. Record resolution separately, with a note about the business outcome. A delivery acknowledgement does not mark work resolved.

For existing idea cards, run `bin/rails athena:backfill_work_items` once after migrating. It creates missing work items and preserves existing operator edits. Existing conversation and idea URLs remain available.

See [the work-intake guide](docs/work_intake.md) for handoff configuration, uncertain delivery handling, and current limitations.

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
ADMIN_USERNAME=your_admin_username
ADMIN_PASSWORD=your_unique_admin_password
ATHENA_TOOL_SECRET=your_unique_tool_secret
TWILIO_ACCOUNT_SID=your_twilio_account_sid
TWILIO_AUTH_TOKEN=your_twilio_auth_token
PUBLIC_BASE_URL=https://YOUR_PUBLIC_BASE_URL
ATHENA_INTERNAL_BASE_URL=http://127.0.0.1:3000
```

Set admin and tool credentials before setting the public origin. A configured public surface fails closed when these credentials are missing.

OpenAI Realtime voice, transcription, noise reduction, turn detection, and advanced session overrides are available in `/admin/app_settings`.

Useful tool and sidecar configuration:

```bash
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

- `docs/work_intake.md` - work queue, staff intake, reviewed handoff, and resolution workflow.
- `docs/positioning.md` - product direction, initial buyer, and boundaries.
- `docs/operations.md` - local setup, runtime configuration, storage, and deployment checks.
- `CONTRIBUTING.md` - development workflow and validation.
- `CHANGELOG.md` - user-visible changes.
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
- This repository does not yet include a license. The owner needs to select one before the project is presented as an open-source package.
