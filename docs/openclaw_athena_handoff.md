# OpenClaw + Athena Handoff

Last updated: 2026-04-28

## Current Goal

Athena is the control plane for Athena, the live OpenAI Realtime phone assistant.

- `Athena` handles the live phone experience.
- `Athena` owns call routing, records, tools, sidecars, and operator surfaces.
- `OpenClaw` agents help with local reasoning, Discord approval workflows, and email execution through Gemma Mail.

## Current Athena Path

- Repo path: `/path/to/athena`
- Local app URL: `http://127.0.0.1:3001`
- Public URL: configure `PUBLIC_BASE_URL` for the active tunnel or deployment
- Twilio routes calls into Athena
- OpenAI Realtime handles the live voice path
- Brave web search is available through Athena tools
- Gemma Mail approval requests route through the Athena approval Discord target

## Important Settings

- `PUBLIC_BASE_URL`
- `OPENAI_API_KEY`
- `OPENAI_REALTIME_MODEL`
- `OPENAI_REALTIME_VOICE`
- `ATHENA_TOOL_SECRET`
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `ATHENA_APPROVAL_CHANNEL`
- `ATHENA_APPROVAL_TARGET`
- `GEMMA_MAIL_GMAIL_ACCOUNT`

## Tool Surface

- `POST /agent_tools/status`
- `POST /agent_tools/web_search`
- `POST /agent_tools/openclaw_chat`
- `POST /agent_tools/athena_calls_latest`
- `POST /agent_tools/athena_call_summary`
- `POST /agent_tools/calendar_availability`
- `POST /agent_tools/gmail_send`
- `POST /agent_tools/command`

## Current Risks

- Keep public tunnel URLs treated as temporary and sensitive.
- Keep `ATHENA_TOOL_SECRET` configured before exposing tool endpoints.
- Keep live SMS disabled until carrier approval and Messaging Service setup are complete.
- Keep healthcare demos synthetic or non-PHI until privacy, compliance, retention, and vendor review are complete.

## Useful Commands

Check Athena settings:

```bash
cd /path/to/athena
bin/rails runner 'puts %w[PUBLIC_BASE_URL OPENAI_REALTIME_MODEL OPENAI_REALTIME_VOICE ATHENA_TOOL_SECRET ATHENA_APPROVAL_TARGET].map { |k| "#{k}=#{AppSetting.find_by(key: k)&.value}" }'
```

Run smoke tests:

```bash
script/smoke_athena_all
script/smoke_twilio_voice
```

Restart Athena locally:

```bash
cd /path/to/athena
rm -f tmp/pids/server.pid
PUBLIC_BASE_URL=https://YOUR_PUBLIC_BASE_URL PORT=3001 bin/rails server -b 0.0.0.0 -p 3001
```

## Summary

The stack is split like this:

- Athena = live OpenAI Realtime phone assistant
- Athena = routing, records, tools, reporting, and approvals
- OpenClaw/Gemma Mail = local sidecars for Discord approval and email execution
