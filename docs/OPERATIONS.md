# Operations

## Status and logs

```bash
./pfif status
ssh azureadmin@$(./pfif outputs | jq -r .public_ip_address.value)
cd /opt/mailcow-dockerized
sudo docker compose ps
sudo docker compose logs --tail=200 postfix-mailcow
```

## Backup

```bash
./pfif backup
```

The native Mailcow backup helper creates `/opt/mailcow-backups/mailcow-*`. When Azure backup storage is enabled, the directory is uploaded to the private blob container with the VM's managed identity. Local backup directories and active Azure backup blobs are expired using `PFIF_BACKUP_RETENTION_DAYS`; Azure soft delete retains deleted blobs for the same additional period.

## Restore

Download a `mailcow-*` backup folder from Azure Blob Storage, or use a local archive containing one. Then:

```bash
./pfif restore /path/to/mailcow-backup.tar.gz
```

Restore is intentionally interactive because the official Mailcow helper asks which restore point and dataset to restore. Take a VM snapshot or fresh backup first.

## Update

```bash
./pfif update
```

PFIF runs a full backup, then Mailcow's official `update.sh --force`. Review Mailcow release notes before major updates.

## Resize

Change `PFIF_VM_SIZE` or disk sizes in `.env`, run `./pfif plan`, then `./pfif apply`. Azure managed disks can grow but cannot shrink. Extend XFS inside the guest after increasing the data disk:

```bash
sudo xfs_growfs /opt
```
