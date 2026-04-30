# Athena Subdomain Handoff

This note is for wiring Athena to a stable public hostname under `example.com`.

## Goal

Keep the existing `example.com` playground/LibreChat environment untouched, and add a dedicated Athena subdomain:

```text
athena.example.com -> AWS tunnel/proxy -> local workstation -> Athena Rails app on localhost:3002
```

## Chosen Approach: AWS Reverse Proxy + Reverse SSH Tunnel

We are not using paid ngrok or Cloudflare Tunnel for this deployment.

The intended architecture is:

```text
Twilio
  -> https://athena.example.com
  -> Route53
  -> small AWS EC2 reverse proxy running Caddy
  -> Caddy reverse_proxy to 127.0.0.1:43002 on the EC2 host
  -> reverse SSH tunnel maintained by local workstation
  -> http://127.0.0.1:3002 on local workstation
  -> Athena Rails app
```

This avoids opening inbound ports on the local workstation or home network. The local workstation dials out to AWS over SSH, and AWS receives public HTTPS/WSS traffic.

## Required Behavior

Athena needs one public HTTPS origin that supports both normal HTTP webhooks and WebSocket upgrades:

```text
https://athena.example.com
wss://athena.example.com/ws/twilio-media
```

Twilio calls `POST /voice/inbound`. Athena responds with TwiML containing a secure WebSocket URL for the Twilio Media Stream. That means the proxy/tunnel path must support:

- valid public TLS certificate
- HTTPS requests to Rails
- `wss://` WebSocket upgrade traffic
- long-lived WebSocket connections for live audio
- no browser-only auth, Zero Trust prompt, or IP allowlist on Twilio webhook paths
- forwarded `Host` and `X-Forwarded-Proto` headers

## AWS Proxy Host Requirements

Use a small dedicated EC2 instance if possible, rather than mixing this into LibreChat infrastructure.

Recommended baseline:

- Ubuntu EC2, tiny instance size is fine
- Elastic IP attached
- Route53 `A` record: `athena.example.com -> Elastic IP`
- Security group:
  - `80/tcp` from `0.0.0.0/0` and `::/0`
  - `443/tcp` from `0.0.0.0/0` and `::/0`
  - `22/tcp` restricted as much as practical
- Caddy installed for automatic HTTPS
- Reverse tunnel port bound only to EC2 localhost: `127.0.0.1:43002`

Do **not** expose port `43002` publicly.

## Caddy Config on AWS Proxy Host

Caddy supports WebSockets automatically. The Caddyfile can be minimal:

```caddyfile
athena.example.com {
  reverse_proxy 127.0.0.1:43002
}
```

Reload Caddy after writing the config:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

## local workstation Reverse Tunnel

On local workstation, Athena should be reachable locally:

```bash
curl -i http://127.0.0.1:3002/up
```

Expected: HTTP `200`.

Generate a dedicated SSH key for the tunnel:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/athena_tunnel -C "athena-tunnel-local"
cat ~/.ssh/athena_tunnel.pub
```

The public key should be installed on the AWS proxy host. Prefer a dedicated low-privilege tunnel user if available.

For a safer dedicated tunnel user, restrict SSH forwarding to the one reverse-listen address Athena needs. Example `/etc/ssh/sshd_config.d/athena-tunnel.conf`:

```sshconfig
Match User athena-tunnel
  AllowTcpForwarding remote
  PermitListen 127.0.0.1:43002
  X11Forwarding no
  AllowAgentForwarding no
  PermitTTY no
  PasswordAuthentication no
```

Then reload SSH:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

If the EC2 host uses the default `ubuntu` user instead, still put the key in `~/.ssh/authorized_keys` for only the account that should maintain the tunnel, and do not reuse a general-purpose SSH key.

Manual tunnel command from local workstation:

```bash
ssh -N \
  -i ~/.ssh/athena_tunnel \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R 127.0.0.1:43002:127.0.0.1:3002 \
  athena-tunnel@ATHENA_PROXY_HOST
```

For durable operation, run the tunnel as a `systemd` service on local workstation.

Example service:

```ini
[Unit]
Description=Athena reverse SSH tunnel to AWS proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=REPLACE_WITH_LOCAL_USER
ExecStart=/usr/bin/ssh -N \
  -i "$HOME/.ssh/athena_tunnel" \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R 127.0.0.1:43002:127.0.0.1:3002 \
  athena-tunnel@ATHENA_PROXY_HOST
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Install and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable athena-tunnel
sudo systemctl restart athena-tunnel
sudo systemctl status athena-tunnel --no-pager
```

## Athena App Settings

Set these in Athena under `/admin/app_settings`:

```text
PUBLIC_BASE_URL=https://athena.example.com
ATHENA_INTERNAL_BASE_URL=http://127.0.0.1:3002
ATHENA_PHONE_NUMBER=+15551234567
OPENAI_REALTIME_MODEL=gpt-realtime-1.5
OPENAI_REALTIME_VOICE=marin
ATHENA_IDEAS_DISCORD_TARGET=channel:YOUR_DISCORD_CHANNEL_ID
```

Also required for live calls:

```text
OPENAI_API_KEY=...
TWILIO_ACCOUNT_SID=...
TWILIO_AUTH_TOKEN=...
TWILIO_VERIFY_WEBHOOK_SIGNATURES=true
```

## Twilio Number Setup

For the Athena Twilio number `+1 555-123-4567`, configure Voice:

```text
A call comes in:
Webhook
POST https://athena.example.com/voice/inbound
```

If a status callback is available, use:

```text
POST https://athena.example.com/voice/outbound/status
```

Athena will generate the media stream URL internally:

```text
wss://athena.example.com/ws/twilio-media
```

## Smoke Tests

After DNS/proxy/tunnel setup:

```bash
curl -i https://athena.example.com/up
```

Expected: HTTP `200`.

Then verify TwiML generation:

```bash
curl -i -X POST https://athena.example.com/voice/inbound \
  -d 'CallSid=CA-athena-subdomain-smoke' \
  -d 'From=+14155552001' \
  -d 'To=+15551234567'
```

Expected: XML response containing:

```text
<Connect>
wss://athena.example.com/ws/twilio-media
provider=openai_realtime
stream_token
```

Then place a real call to `+1 555-123-4567` and check:

```text
https://athena.example.com/admin/conversations
https://athena.example.com/admin/idea_captures
```

## Safety Notes

- Leave `example.com` itself pointed at LibreChat.
- Do not expose local workstation inbound ports.
- Do not expose `.env`, logs, SQLite files, or local service ports directly.
- Do not expose EC2 tunnel port `43002`; it must remain localhost-only.
- Use a dedicated SSH key for the tunnel.
- Prefer a low-privilege tunnel user on the AWS proxy host.
- Enable admin auth before sharing the public admin UI broadly.
- Enable Twilio webhook signature verification before using a public tunnel.
- Keep Rails bound to `127.0.0.1`; only the SSH reverse tunnel should reach it.
- Healthcare demos should avoid PHI. Athena is currently a demo/workshop ideation stack, not a production clinical system.
