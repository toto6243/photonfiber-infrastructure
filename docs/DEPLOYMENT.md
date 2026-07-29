# Deployment

## 1. Prepare the workstation

Install Azure CLI, OpenTofu 1.12+, Ansible, Git, Python 3, jq, curl, rsync and OpenSSH. Then authenticate:

```bash
az login --tenant b5d9eb9a-edb1-43df-be5d-87be76aa7dd8
az account set --subscription 1fbb027b-5835-4069-a5e2-c60815358d1a
```

## 2. Configure

```bash
cp .env.example .env
```

Review every value. The state storage defaults point to the existing `PhotonFiber-Terraform/pfterraform6243/tfstate` backend. `PFIF_SSH_ALLOWED_CIDRS=AUTO` restricts SSH to the workstation's current public IPv4.

For Cloudflare automation, create a scoped token with DNS edit permission for `photonfiber.pk`, add the token, leave `PFIF_CLOUDFLARE_ZONE_ID=AUTO`, and enable `PFIF_MANAGE_CLOUDFLARE_DNS`.

## 3. Preview and deploy

```bash
./pfif plan
./pfif deploy
```

The deployment is idempotent. Rerun `./pfif ansible` after changing Mailcow settings, or rerun `./pfif deploy` to reconcile everything.

## 4. Complete Mailcow setup

1. Browse to `https://mail.photonfiber.pk`.
2. Sign in with `admin` / `moohoo` and change the administrator password immediately.
3. Add `photonfiber.pk` as a mail domain.
4. Create required mailboxes and aliases, including `postmaster`, `abuse` and the DMARC reporting mailbox.
5. Copy the DKIM TXT value from **Configuration → ARC/DKIM keys** to Cloudflare.
6. Run `./pfif validate` after DNS and certificate propagation.

## SMTP prerequisite

Direct mail delivery requires outbound TCP/25 from the Azure VM. Check the subscription type and Azure networking policy before production use. A successful inbound NSG rule does not guarantee Azure permits outbound SMTP.
