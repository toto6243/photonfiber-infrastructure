# Photon Fiber Infrastructure Framework (PFIF)

A ready-to-run VS Code repository that deploys a dedicated Mailcow server on Azure with OpenTofu, configures the host with Ansible, optionally creates Cloudflare DNS records, assigns managed-identity access to Azure Blob backups, and provides day-two operations commands.

## What it deploys

- Dedicated Azure resource group, VNet, subnet, NSG, static Standard public IPv4 and Ubuntu 24.04 VM
- Separate managed data disk mounted at `/opt`
- System-assigned managed identity
- Private Azure Blob backup container with RBAC-based uploads, lifecycle retention and no stored SAS token
- Mailcow on the stable `master` branch using current Docker Engine and Compose plugin
- Automated daily Mailcow backups, unattended security updates and SSH hardening
- Optional Cloudflare A, MX, SPF, DMARC, autoconfig and autodiscover records
- Optional Azure PTR/rDNS after forward DNS is live
- Optional authenticated SMTP relay over STARTTLS/587 or implicit TLS/465

## First deployment

1. Extract the project and open the folder in VS Code.
2. In the integrated terminal:

```bash
cp .env.example .env
code .env
```

3. Review `.env`. It is sourced as a shell file, so quote values that contain spaces. To automate Cloudflare DNS, set `PFIF_MANAGE_CLOUDFLARE_DNS=true` and add the API token. `PFIF_CLOUDFLARE_ZONE_ID=AUTO` discovers the zone automatically.
4. Deploy:

```bash
./pfif deploy
```

The command validates prerequisites, bootstraps remote state, applies Azure resources, generates Ansible inventory, waits for SSH, installs Mailcow, attempts PTR/rDNS and runs non-blocking public-service checks. DNS/TLS/PTR checks may remain pending until records propagate.

## Essential commands

```bash
./pfif plan                 # preview Azure/DNS changes
./pfif apply                # apply infrastructure only
./pfif ansible              # configure or repair the VM
./pfif status               # show outputs and Mailcow container status
./pfif dns                  # print required DNS records and DKIM next step
./pfif rdns                 # configure Azure PTR after A record resolves
./pfif backup               # start a backup now
./pfif restore BACKUP       # interactive restore from a local archive/directory
./pfif update               # backup, then update Mailcow non-interactively
./pfif validate             # check DNS, ports, HTTPS and SMTP banner
./pfif destroy              # destroy workload resources
```

VS Code tasks expose the same actions through **Terminal → Run Task**.

## Prerequisites

Install Azure CLI, OpenTofu, Ansible, Git, Python 3, jq, curl, rsync, SSH and SCP. Log in before deployment:

```bash
az login --tenant b5d9eb9a-edb1-43df-be5d-87be76aa7dd8
az account set --subscription 1fbb027b-5835-4069-a5e2-c60815358d1a
```

Azure subscriptions commonly block outbound TCP/25. Configure the authenticated relay variables in `.env` before deployment unless your subscription is explicitly allowed to deliver mail directly. See `docs/SMTP_RELAY.md`.

## After deployment

Open `https://mail.photonfiber.pk`. Sign in with Mailcow's default credentials `admin` / `moohoo`, then change the password immediately. Add `photonfiber.pk` in the Mailcow UI, then publish the DKIM TXT value shown under **Configuration → ARC/DKIM keys**. DNS and operational details are in `docs/`.

## Security

`.env`, generated inventory, generated variables, state and keys are ignored by Git. Cloudflare credentials stay local and are passed to the provider through environment variables. Azure backup access uses the VM's managed identity.
