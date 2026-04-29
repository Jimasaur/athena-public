# Testing Sidecar Flow

Athena's safe test path should avoid live SMS or email unless explicitly requested.

## Local Smoke Suite

```sh
script/smoke_athena_all
```

This runs:

- `script/smoke_agent_tools`
- `script/smoke_twilio_voice`
- `script/smoke_sidecar_review_execute`

## What Each Script Covers

`script/smoke_agent_tools`

Exercises the Athena tool surface directly, including status, lookup, web search, OpenClaw chat, and email handoff behavior.

`script/smoke_twilio_voice`

Exercises Twilio inbound TwiML generation, OpenAI Realtime media stream parameters, status callbacks, optional transcription callbacks, conversation creation, and call state creation.

`script/smoke_sidecar_review_execute`

Creates a synthetic completed conversation, runs the post-call sidecar draft flow, approves the draft, and executes it with a fake Twilio client unless `LIVE_SMS=1`.

## Live SMS Safety

Default smoke runs do not send live SMS.

To send live SMS intentionally:

```sh
LIVE_SMS=1 SMS_TO=+15555550123 script/smoke_sidecar_review_execute
```

Only use that after the 10DLC campaign and Messaging Service are approved and configured.

## Email Approval Flow

For live Discord approval testing:

```sh
bin/rails runner 'puts AppSetting.fetch("ATHENA_APPROVAL_TARGET")'
script/watch_gemma_mail_approvals
```

Then ask Athena for an email during a call. Athena should create an `email_approval.queued` event, enqueue `GemmaMailApprovalJob`, post to Discord, and process an affirmative reply through `GemmaMailDiscordApprovalPoller`.

## Useful Test Commands

```sh
bin/rails test
bin/rails test:system
bin/ci
```

Focused Realtime and tool tests:

```sh
bin/rails test test/requests/twilio_voicebot_compatibility_test.rb test/lib/openai_realtime_twilio_bridge_test.rb test/requests/agent_tools_controller_test.rb
```
