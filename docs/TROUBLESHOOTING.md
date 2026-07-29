# Troubleshooting

## OpenTofu backend authorization

Run `./pfif init` again after 1–5 minutes. Azure RBAC assignments can take time to propagate. Confirm the signed-in account has `Storage Blob Data Contributor` on `pfterraform6243`.

## VM SKU unavailable

Change `PFIF_VM_SIZE` in `.env`. Keep at least 8 GiB RAM for the default feature set. Leave `PFIF_AVAILABILITY_ZONE` blank unless the chosen SKU is available in that zone.

## SSH timeout

Your public IP may have changed. Keep `PFIF_SSH_ALLOWED_CIDRS=AUTO`, run `./pfif apply`, then retry. Confirm Azure NSG rule `Allow-SSH-Trusted` contains your current `/32`.

## Mailcow certificate remains self-signed

Confirm A, autoconfig and autodiscover records resolve directly to the Azure public IP, with Cloudflare proxy disabled. Ports 80 and 443 must be reachable. Check:

```bash
sudo docker compose logs --tail=200 acme-mailcow
```

## Outbound mail fails

Test from the VM:

```bash
nc -vz gmail-smtp-in.l.google.com 25
```

If TCP/25 is blocked, request Azure SMTP access where eligible or use an authenticated SMTP relay and configure Mailcow accordingly.

## Backup upload fails

Confirm the VM identity role assignment and login:

```bash
az login --identity
az role assignment list --assignee $(az vm show -g pfif-prod-rg -n pfif-prod-mail --query identity.principalId -o tsv) -o table
systemctl status pfif-mailcow-backup.service
journalctl -u pfif-mailcow-backup.service -n 200
```
