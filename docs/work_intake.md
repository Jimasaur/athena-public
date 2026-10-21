# Work intake and coordination

Athena keeps an incoming request, its source context, operator decisions, and handoff results together. This slice adds a work layer above the existing voice and idea-capture records. It does not replace the team's downstream work system.

## Local walkthrough

```bash
bin/rails db:migrate
script/seed_work_queue_demo
bin/dev
```

Open `/admin`. The seed script refreshes only the named synthetic conversation scenarios and the named synthetic staff request. Synthetic work items carry a persistent demo marker; their handoffs always simulate delivery without DNS or network requests.

Use **New work item** to enter a staff request. This is an authenticated internal form, with no automatic AI extraction. It stores the description as the source text. Assign an owner, priority, due date, and next step, then move through needs review, ready, in progress, waiting, resolved, or archived. Resolution requires a note; reopening clears the current resolution timestamp while event history retains earlier changes.

Owners are text labels in this prototype. They are not user accounts, notifications, permissions, or verified identity. The existing admin authentication protects the workspace. Team identity, roles, assignments to real users, and notifications remain future work.

## Voice and idea context

New voice idea captures create one linked opportunity work item. Repeated captures reuse the existing work item and preserve operator edits. Legacy idea cards can be linked with:

```bash
bin/rails athena:backfill_work_items
```

This is idempotent and does not infer a resolution from idea review or an executed follow-up action. Source conversation and idea deletion leave the independent work record available; deleted source material cannot be opened. Refreshing a named synthetic scenario deliberately replaces its own synthetic work items.

The current voice interface retains its existing idea-capture contract. General voice request templates and additional input channels are expansion work. The staff web form provides the second intake path now.

## Reviewed downstream handoff

One generic JSON webhook adapter connects to a downstream system. Live delivery is off by default:

```text
ATHENA_HANDOFF_ENABLED=false
ATHENA_HANDOFF_WEBHOOK_URL=
ATHENA_HANDOFF_WEBHOOK_BEARER=
```

Configure the real endpoint through **Connections** or process environment, then deliberately enable handoff. Use a public HTTPS endpoint without credentials, query parameters, or fragments. Put authentication in the bearer header. Existing database settings take precedence over environment variables.

Preparation saves a payload, destination, mode, and work-item revision. Approval authorizes that saved snapshot. Editing the work item or changing its destination before delivery requires preparing and reviewing a new snapshot. Delivering requires a separate operator action; creation, capture, assignment, and approval alone do not send anything.

The request includes an `Idempotency-Key`. The receiver must honor it to deduplicate requests; Athena cannot guarantee a third-party side effect occurs exactly once. An HTTP success records acknowledgement, not business completion.

A timeout, failed response, or uncertain delivery enters an **Unknown** state. Check the receiving system and reconcile with evidence before preparing a replacement. Athena does not blindly resend an uncertain request. The handoff history and operator evidence stay attached to the work item. A process interruption during delivery may also need reconciliation.

## Product boundaries

Available now: staff web intake, voice-idea conversion, a shared queue, editable work records, source links, audited changes, optimistic locking, reviewed webhook handoff, and explicit resolution notes.

Still planned: email ingestion, shared-inbox capture, user accounts and roles, automatic assignment, scheduled reminders, broader voice capture schemas, connector-specific reconciliation, and outcome metrics validated against downstream records. Event history is useful for review; it is not an immutable or compliance-certified audit system.
