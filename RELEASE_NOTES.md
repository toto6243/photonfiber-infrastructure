# PFIF 1.1.0

- Added idempotent authenticated SMTP relay support for Mailcow.
- Supports STARTTLS on port 587 and implicit TLS on port 465.
- Stores relay credentials in a mode-0600 Postfix map and never in OpenTofu state.
- Added provider-domain-authentication and SPF/DKIM guidance.
- Fixed macOS Bash 3.2 compatibility in `truthy()`.
- Fixed AzureRM backend Azure CLI authentication by omitting backend `tenant_id`.
