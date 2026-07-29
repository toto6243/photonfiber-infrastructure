# DNS

Run `./pfif dns` to print the exact records generated from the OpenTofu state.

Required records:

| Type | Name | Target/value | Cloudflare proxy |
|---|---|---|---|
| A | mail.photonfiber.pk | Azure public IPv4 | DNS only |
| MX | photonfiber.pk | mail.photonfiber.pk, priority 10 | n/a |
| TXT | photonfiber.pk | `v=spf1 mx -all` | n/a |
| TXT | _dmarc.photonfiber.pk | policy emitted by PFIF | n/a |
| CNAME | autoconfig.photonfiber.pk | mail.photonfiber.pk | DNS only |
| CNAME | autodiscover.photonfiber.pk | mail.photonfiber.pk | DNS only |
| TXT | DKIM selector shown by Mailcow | value shown by Mailcow | n/a |

Never enable Cloudflare's orange-cloud proxy for SMTP, IMAP, POP3 or the Mailcow hostname. Cloudflare DNS automation intentionally sets the web-related mail records to DNS-only.

Azure PTR/rDNS is set by `./pfif rdns`. Azure first validates that `mail.photonfiber.pk` resolves to the same public IP, so forward DNS must be live before the command succeeds.
