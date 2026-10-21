# Contributing to Athena

Athena is a Rails development prototype. Keep changes focused on a reviewable operator workflow and validate the behavior with synthetic records.

## Setup

Use Ruby 3.4.7, Bundler 4.0.2, and a POSIX shell. Follow the [README](README.md#fast-path), keep provider credentials blank, and seed the demo scenarios. The app uses importmaps and the Tailwind Ruby binary; there is no npm build step.

## Before opening a pull request

```bash
bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
script/public_readiness_check
```

Use focused regression tests for changes to approvals, tool authorization, external actions, and state transitions. Provider calls in automated tests must use fakes. Check operator pages at desktop and mobile widths when changing templates.

Document which checks actually ran, and identify any blocked checks. Do not report a configured integration as a tested live connection.

## Code and data conventions

- Read configuration through `AppSetting.fetch` so database settings retain precedence.
- Keep network and process calls in services and use `OutboundUrlPolicy` for configurable outbound URLs.
- Keep approval text explicit. Ambiguous or negated replies must never authorize a send.
- Record review decisions and external action outcomes in the conversation audit trail.
- Preserve dry-run behavior for synthetic scenarios.
- Never commit `.env`, database files, logs, recordings, credentials, or private deployment notes.

The public repository and private deployment are separate checkouts. Transfer reviewed changes deliberately; do not copy private configuration or history into the public reference.
