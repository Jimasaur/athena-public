# Athena Demo Walkthrough

Use this walkthrough when you want one stable page that shows what Athena is becoming.

## Create The Demo

Open the launchpad:

```text
http://127.0.0.1:3001/admin/demo_scenarios
```

Use the **Seed all demos** button on that page for the fastest setup.

Seed all four retreat workflow scenarios:

```sh
script/seed_demo_scenarios
```

The script prints admin URLs for each seeded conversation.

The older single guided demo is still available:

```sh
script/seed_demo_conversation
```

The script prints an admin URL like:

```text
http://127.0.0.1:3001/admin/conversations/40
```

The demo data is idempotent. Running either seed script again replaces the matching demo conversation records.

## What To Show

1. Open `/admin/demo_scenarios`.
2. Use the Live Call Demo panel to call the mapped Twilio number.
3. Share a revenue cycle automation, innovation, cost savings, or workflow idea and ask Athena to capture it for the retreat.
4. Use the Live monitor card to open the newest call.
5. Launch or refresh seeded scenarios for ideation, automation discovery, denials savings, and review library workflows.
6. Open the conversation and start with the Operator brief.
7. Move to the transcript and timeline: they show the complete operational chain.
8. Point out call state: provider, use case, review state, intent, risk, and sidecar patches.
9. Open the Ideas page: Athena produced a structured idea card linked to the call.
10. For demo-marked drafts, execution records a dry-run audit instead of sending live SMS.

## Demo Story

Athena is not just a voice bot. It is an operations layer around voice AI:

```text
call -> transcript -> call state -> idea capture -> Discord report -> review library -> audit trail
```

For seeded scenarios and demo-marked drafts, SMS execution is represented by a fake Twilio message SID:

```text
SM-DEMO-...
```

Live SMS delivery should wait until the A2P campaign is approved and the Athena number is attached to the registered Messaging Service.

## Reset

Run the seed script again:

```sh
script/seed_demo_scenarios
script/seed_demo_conversation
```
