# Architecture

```text
Internet
   |
Cloudflare DNS (optional automation, DNS-only)
   |
Static Azure Standard Public IPv4 + PTR
   |
Network Security Group
   |
Ubuntu 24.04 Gen2 VM (system-assigned identity)
   |-- OS disk: Standard SSD
   |-- Data disk mounted at /opt
   |     |-- /opt/mailcow-dockerized
   |     `-- /opt/mailcow-backups
   |
Mailcow Docker Compose stack
   |
Azure Blob Storage (private container, RBAC upload)
```

The workload is isolated in a dedicated resource group and VNet. SSH is limited to CIDRs generated from `.env`; mail and web ports are public. The backup account disables shared-key authentication, so the VM uploads with its managed identity and the `Storage Blob Data Contributor` role.

The default `Standard_B2s_v2` VM has 2 vCPUs and 8 GiB RAM. FTS is disabled by default to reduce memory and I/O pressure; ClamAV and SOGo remain enabled. Increase the VM size and data disk before serving a larger user base.
