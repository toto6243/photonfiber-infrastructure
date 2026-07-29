# Security

- Keep `.env`, generated tfvars, inventory, state and SSH keys out of Git.
- Use a Cloudflare token scoped only to DNS edit for the single zone.
- SSH is key-only and restricted by Azure NSG to configured CIDRs.
- Root login and password authentication are disabled.
- Azure Blob backup uploads use managed identity; shared storage keys are disabled.
- The Mailcow host is dedicated and does not expose Docker's remote API.
- Keep `ENABLE_IPV6=false` unless Azure IPv6 and Mailcow IPv6 are configured end to end.
- Change Mailcow's initial administrator password immediately and enable MFA.
- Publish SPF, DKIM, DMARC and PTR, then monitor blocklists and delivery reports.
- Test restores regularly. A backup that has not been restored is unverified.

Do not store mailbox passwords, Cloudflare tokens or Azure credentials in repository files. Rotate the Cloudflare token if it is ever printed, committed or shared.
