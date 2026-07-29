# Authenticated SMTP relay

PFIF can route all Mailcow outbound delivery through an authenticated SMTP relay. This avoids Azure outbound TCP/25 restrictions while keeping inbound SMTP, submission, IMAP, webmail, antispam, calendars and mailboxes on Mailcow.

## Configure

Add the provider values to `.env`:

```bash
PFIF_SMTP_RELAY_ENABLED=true
PFIF_SMTP_RELAY_HOST=smtp.example-provider.com
PFIF_SMTP_RELAY_PORT=587
PFIF_SMTP_RELAY_USERNAME='provider-username'
PFIF_SMTP_RELAY_PASSWORD='provider-password-or-api-key'
PFIF_SMTP_RELAY_TLS_MODE=starttls
```

Use `starttls` for port 587. Use `implicit_tls` only when the provider explicitly requires port 465. Quote credentials in `.env`, especially when they contain shell metacharacters. Never commit `.env`.

Run `./pfif ansible` to apply relay settings to an existing server, or `./pfif deploy` for a new deployment. The role writes a persistent PFIF block to `data/conf/postfix/extra.cf`, stores credentials with mode 0600, builds an LMDB map inside the Postfix container, restarts Postfix and verifies the loaded relay endpoint.

## Provider-side requirements

Before sending production mail, verify `photonfiber.pk` with the relay provider and publish every SPF/DKIM/return-path record the provider supplies. PFIF's default SPF value (`v=spf1 mx -all`) is not sufficient for most relay services. Never publish more than one SPF TXT record; merge the provider's include/mechanism into one record.

## Disable

Set `PFIF_SMTP_RELAY_ENABLED=false` and run `./pfif ansible`. PFIF removes its managed Postfix block and relay credential files.
