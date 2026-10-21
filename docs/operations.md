# Running Athena

## Local evaluation

Use Ruby 3.4.7 and Bundler 4.0.2. Linux, macOS, and WSL support the documented POSIX shell scripts. On Linux, native gem compilation may require a compiler, Ruby headers, libyaml, pkg-config, and SQLite development headers. Image processing additionally needs libvips. A modern browser is required for the console. The current system tests use RackTest; also inspect the running app in a real browser when changing interactions or layout.

```bash
cp .env.example .env
bin/setup --skip-server
bin/doctor
script/seed_demo_scenarios
bin/dev
```

Open `http://127.0.0.1:3000/admin` for the work queue, or `/admin/demo_scenarios` for the existing voice examples. Run `script/seed_work_queue_demo` to populate a synthetic intake/assignment walkthrough. The checked-in example leaves provider credentials and `PUBLIC_BASE_URL` blank. Local development allows an unconfigured admin login only when the app is not configured as a public surface. Keep this tour on your machine and use synthetic data.

`PORT=3001 bin/dev` overrides the example port. `bin/dev` uses Foreman to load `.env`. Standalone Rails commands do not automatically load `.env`; export the values they need in the process environment. `bin/doctor` loads `.env` itself and reports local checks.

The development server binds to `127.0.0.1` by default. Set `ATHENA_BIND` explicitly only after configuring authentication if you need another interface. The default development process starts the web server and CSS watcher. Start `script/watch_gemma_mail_approvals` separately when intentionally evaluating configured live approvals; it does not run during the default local tour.

## Configuration precedence

`AppSetting.fetch` reads the database first, then the process environment. A stored empty string overrides the environment too. Edit or remove the database value in **Config** when an environment change appears to have no effect. Restart processes after changing environment variables. Rails boot configuration, including Action Cable origins, reads process environment directly.

The dashboard and demo readiness panels inspect configuration without sending network requests. **Configured** means settings are present and pass local checks. **Needs review** includes sample values and incomplete security settings. Verify a real call and inspect its transcript/tool events before describing a live integration as working.

## Container package

The Dockerfile builds a production image with precompiled assets and a non-root runtime:

```bash
docker build -t athena .
```

Supply runtime settings through your deployment's secret manager or protected environment file. Set a persistent `SECRET_KEY_BASE` (or your Rails credentials/master key), `ADMIN_USERNAME`, `ADMIN_PASSWORD`, and `ATHENA_TOOL_SECRET`. Never bake these values into the image. Keep `/rails/storage` on a persistent volume; it contains the SQLite databases and local files. The image exposes port 80 through Thruster and prepares databases on server startup.

`config/deploy.yml` is a starting template, with placeholder infrastructure. Review it before using Kamal. Run one SQLite-backed application instance unless you explicitly design and test a shared database arrangement. Enable the Solid Queue supervisor or run `bin/jobs` for background jobs. OpenClaw and its approval/mail helpers are optional host integrations and are not installed in the base Docker image.

## Live voice evaluation

1. Set the actual HTTPS `PUBLIC_BASE_URL`, Twilio account credentials, and OpenAI configuration.
2. Configure an agent profile with the inbound Twilio number.
3. Require admin/tool authentication and enable Twilio signature verification.
4. Terminate HTTPS and configure forwarded headers and Action Cable origins for that deployment.
5. Configure optional Discord destinations and explicit approver IDs before evaluating email approval.
6. Place a controlled test call and inspect the conversation, transcript roles, tool results, and pending actions.

Phone calls, search, Discord delivery, and approved email use their configured providers. They may incur provider costs. The synthetic tour does not establish that any provider integration is healthy.

## Work layer upgrades

Run `bin/rails db:migrate`, then `bin/rails athena:backfill_work_items` to link existing idea cards without replacing operator-edited work. The default console entry is now the work queue; the prior dashboard is available at `/admin/overview`. Existing idea, conversation, and demo URLs remain available.

Live webhook handoff remains disabled until `ATHENA_HANDOFF_ENABLED=true` and a valid `ATHENA_HANDOFF_WEBHOOK_URL` are configured. See [work intake](work_intake.md) for review, deduplication requirements, and uncertain-delivery reconciliation.

## Data and release operations

Back up the storage volume and test restoration before relying on a deployment. Decide retention for transcripts, recordings, idea exports, and audit events. CSV exports contain caller and conversation content; handle them as part of that data policy.

Run the checks in [CONTRIBUTING](../CONTRIBUTING.md) before sharing a build. Preserve the separation between the sanitized public source and the private runtime. A source review and passing tests do not establish production readiness.
