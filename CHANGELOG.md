# Changelog

## Unreleased

### Product

- Reposition Athena around work intake and coordination, with a work queue as the console entry point.
- Add requests, issues, opportunities, and follow-ups with ownership, priority, due dates, resolution notes, and event history.
- Connect new voice idea captures to work items and add staff web intake.
- Add explicit prepare/approve/deliver handoffs, saved revision checks, simulated delivery, and uncertain-delivery reconciliation.
- Search and filter the Ideas library, page through results, and export matching cards as CSV.
- Mark ideas reviewed, archive them, and reopen them with timeline audit events.
- Show configuration status separately from local synthetic demo availability and live provider health.
- Label completed demo actions as simulated instead of claiming a message was sent.
- Clarify Athena's voice operations purpose and label the landing-page scenario as illustrative.

### Reliability

- Require an explicit affirmative reply for Discord email approval; negated and ambiguous replies do not send.
- Keep the latest revised Discord approval actionable while ignoring superseded approval messages.

### Package

- Align the example environment and local tour on port 3000, leaving the public URL unset.
- Bind local development to loopback and make the live approval poller an explicit separate process.
- Document runtime prerequisites, configuration precedence, operations, and contribution checks.
- Use Athena naming in container instructions and exclude test gems from the production image.
- Refresh compatible dependencies, including Rails 8.1.4, to address the dependency audit findings.
