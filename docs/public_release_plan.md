# Public Release Plan

Athena can be shared publicly as source code, while a private deployment keeps running from a private checkout.

## Recommended Split

```text
Private live repo or branch
  -> real hostnames, phone numbers, Discord channels, local deployment notes
  -> running local instance

Public template repo or branch
  -> placeholder config, generic deployment notes, no private history
  -> shareable reference implementation
```

Do not make a private live repository public without cleaning history. If a repository has ever contained live phone numbers, channel IDs, hostnames, or deployment notes, create a fresh public repository from the sanitized template branch instead.

## Safe Public Branch

The `public-template` branch is intended to be an orphan branch with a single sanitized root commit. It should not contain private branch history.

Before publishing, run:

```bash
script/public_readiness_check
bin/rails test
bin/rubocop
```

## Live Instance Safety

The running instance should continue to use its private checkout and DB-backed `AppSetting` values. Sanitizing `.env.example`, seeds, and docs in the public template does not change a running local database.

Before broadly sharing a live public endpoint, set:

```text
ADMIN_USERNAME
ADMIN_PASSWORD
ATHENA_TOOL_SECRET
TWILIO_VERIFY_WEBHOOK_SIGNATURES=true
TWILIO_ALLOWED_CALLERS if appropriate
```

Keep real `.env` files, SQLite databases, logs, recordings, SSH keys, Rails master keys, and deployment-specific tunnel notes out of public repositories.
