#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env
require_cmd python3
require_cmd az

required=(
  PFIF_AZURE_SUBSCRIPTION_ID PFIF_AZURE_TENANT_ID PFIF_AZURE_LOCATION
  PFIF_STATE_RESOURCE_GROUP PFIF_STATE_STORAGE_ACCOUNT PFIF_STATE_CONTAINER PFIF_STATE_KEY
  PFIF_PROJECT_NAME PFIF_ENVIRONMENT PFIF_MAIL_DOMAIN PFIF_MAIL_HOSTNAME
  PFIF_ADMIN_USERNAME PFIF_SSH_PUBLIC_KEY_PATH PFIF_SSH_PRIVATE_KEY_PATH
)
for key in "${required[@]}"; do
  [[ -n "${!key:-}" ]] || die "Required .env value is empty: $key"
done

az account set --subscription "$PFIF_AZURE_SUBSCRIPTION_ID"

if truthy "${PFIF_MANAGE_CLOUDFLARE_DNS:-false}"; then
  resolve_cloudflare_zone_id
fi

if [[ "${PFIF_SSH_ALLOWED_CIDRS:-AUTO}" == "AUTO" ]]; then
  info "Detecting current public IPv4 for SSH restriction"
  detected_ip="$(curl -4fsS --max-time 15 https://api.ipify.org || true)"
  [[ "$detected_ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || die "Could not detect public IPv4. Set PFIF_SSH_ALLOWED_CIDRS manually."
  export PFIF_EFFECTIVE_SSH_ALLOWED_CIDRS="$detected_ip/32"
else
  export PFIF_EFFECTIVE_SSH_ALLOWED_CIDRS="$PFIF_SSH_ALLOWED_CIDRS"
fi

export PFIF_EXPANDED_SSH_PUBLIC_KEY_PATH="$(expand_path "$PFIF_SSH_PUBLIC_KEY_PATH")"
export PFIF_EXPANDED_SSH_PRIVATE_KEY_PATH="$(expand_path "$PFIF_SSH_PRIVATE_KEY_PATH")"
[[ -f "$PFIF_EXPANDED_SSH_PUBLIC_KEY_PATH" ]] || die "SSH public key not found: $PFIF_EXPANDED_SSH_PUBLIC_KEY_PATH"
[[ -f "$PFIF_EXPANDED_SSH_PRIVATE_KEY_PATH" ]] || die "SSH private key not found: $PFIF_EXPANDED_SSH_PRIVATE_KEY_PATH"

mkdir -p "$TOFU_DIR" "$ANSIBLE_DIR/inventory/group_vars/mailcow"

python3 <<'PY'
from pathlib import Path
import ipaddress, json, os, re

root = Path(os.environ['PFIF_ROOT'])
tofu = root / 'tofu/environments/prod'
ansible = root / 'ansible'

def env(name, default=''):
    return os.environ.get(name, default)

def boolean(name, default='false'):
    return env(name, default).strip().lower() in {'true','yes','y','1'}

def integer(name, default):
    return int(env(name, str(default)))

def hcl(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return '[' + ', '.join(json.dumps(v) for v in value) + ']'
    return json.dumps(value)

cidrs = [x.strip() for x in env('PFIF_EFFECTIVE_SSH_ALLOWED_CIDRS').split(',') if x.strip()]
zone = env('PFIF_AVAILABILITY_ZONE').strip() or None
manage_cf = boolean('PFIF_MANAGE_CLOUDFLARE_DNS')
cf_zone = (env('PFIF_CLOUDFLARE_ZONE_ID').strip() or None) if manage_cf else None

domain = env('PFIF_MAIL_DOMAIN').strip().lower()
hostname = env('PFIF_MAIL_HOSTNAME').strip().lower()
if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+', domain):
    raise SystemExit('PFIF_MAIL_DOMAIN must be a valid lowercase DNS domain')
if hostname == domain or not hostname.endswith('.' + domain):
    raise SystemExit('PFIF_MAIL_HOSTNAME must be a host below PFIF_MAIL_DOMAIN')

try:
    vnet = ipaddress.ip_network(env('PFIF_VNET_ADDRESS_SPACE', '10.40.0.0/16'), strict=True)
    subnet = ipaddress.ip_network(env('PFIF_SUBNET_ADDRESS_PREFIX', '10.40.1.0/24'), strict=True)
    private_ip = ipaddress.ip_address(env('PFIF_PRIVATE_IP_ADDRESS', '10.40.1.10'))
    parsed_cidrs = [ipaddress.ip_network(c, strict=False) for c in cidrs]
except ValueError as exc:
    raise SystemExit(f'Invalid network configuration: {exc}') from exc
if not subnet.subnet_of(vnet):
    raise SystemExit('PFIF_SUBNET_ADDRESS_PREFIX must be contained in PFIF_VNET_ADDRESS_SPACE')
if private_ip not in subnet or private_ip in {subnet.network_address, subnet.broadcast_address}:
    raise SystemExit('PFIF_PRIVATE_IP_ADDRESS must be a usable address inside PFIF_SUBNET_ADDRESS_PREFIX')
if not parsed_cidrs:
    raise SystemExit('At least one SSH allowed CIDR is required')
if manage_cf and not cf_zone:
    raise SystemExit('Cloudflare zone ID discovery did not return a value')

values = {
    'subscription_id': env('PFIF_AZURE_SUBSCRIPTION_ID'),
    'tenant_id': env('PFIF_AZURE_TENANT_ID'),
    'project_name': env('PFIF_PROJECT_NAME', 'pfif'),
    'environment': env('PFIF_ENVIRONMENT', 'prod'),
    'location': env('PFIF_AZURE_LOCATION', 'uaenorth'),
    'mail_domain': domain,
    'mail_hostname': hostname,
    'admin_username': env('PFIF_ADMIN_USERNAME', 'azureadmin'),
    'admin_ssh_public_key_path': env('PFIF_EXPANDED_SSH_PUBLIC_KEY_PATH'),
    'ssh_allowed_cidrs': cidrs,
    'vm_size': env('PFIF_VM_SIZE', 'Standard_B2s_v2'),
    'os_disk_size_gb': integer('PFIF_OS_DISK_SIZE_GB', 64),
    'data_disk_size_gb': integer('PFIF_DATA_DISK_SIZE_GB', 128),
    'os_disk_type': env('PFIF_OS_DISK_TYPE', 'StandardSSD_LRS'),
    'data_disk_type': env('PFIF_DATA_DISK_TYPE', 'StandardSSD_LRS'),
    'availability_zone': zone,
    'accelerated_networking_enabled': boolean('PFIF_ACCELERATED_NETWORKING'),
    'encryption_at_host_enabled': boolean('PFIF_ENCRYPTION_AT_HOST'),
    'vnet_address_space': [env('PFIF_VNET_ADDRESS_SPACE', '10.40.0.0/16')],
    'subnet_address_prefixes': [env('PFIF_SUBNET_ADDRESS_PREFIX', '10.40.1.0/24')],
    'private_ip_address': env('PFIF_PRIVATE_IP_ADDRESS', '10.40.1.10'),
    'create_backup_storage': boolean('PFIF_CREATE_BACKUP_STORAGE', 'true'),
    'backup_replication_type': env('PFIF_BACKUP_REPLICATION_TYPE', 'LRS'),
    'backup_retention_days': integer('PFIF_BACKUP_RETENTION_DAYS', 14),
    'manage_cloudflare_dns': manage_cf,
    'cloudflare_zone_id': cf_zone,
}

tfvars = '\n'.join(f'{k:<31} = {hcl(v)}' for k, v in values.items()) + '\n'
(tofu / 'terraform.tfvars').write_text(tfvars)

backend = {
    'resource_group_name': env('PFIF_STATE_RESOURCE_GROUP'),
    'storage_account_name': env('PFIF_STATE_STORAGE_ACCOUNT'),
    'container_name': env('PFIF_STATE_CONTAINER'),
    'key': env('PFIF_STATE_KEY'),
    'use_azuread_auth': True,
    'subscription_id': env('PFIF_AZURE_SUBSCRIPTION_ID'),
}
backend_text = '\n'.join(f'{k:<22} = {hcl(v)}' for k, v in backend.items()) + '\n'
(tofu / 'backend.hcl').write_text(backend_text)

relay_enabled = boolean('PFIF_SMTP_RELAY_ENABLED')
relay_host = env('PFIF_SMTP_RELAY_HOST').strip()
relay_port = integer('PFIF_SMTP_RELAY_PORT', 587)
relay_username = env('PFIF_SMTP_RELAY_USERNAME').strip()
relay_password = env('PFIF_SMTP_RELAY_PASSWORD')
relay_tls_mode = env('PFIF_SMTP_RELAY_TLS_MODE', 'starttls').strip().lower()
if relay_enabled:
    if not relay_host or any(ch in relay_host for ch in '[]:/\\ \t\r\n'):
        raise SystemExit('PFIF_SMTP_RELAY_HOST must be a hostname without brackets, scheme, port, or whitespace')
    if not (1 <= relay_port <= 65535):
        raise SystemExit('PFIF_SMTP_RELAY_PORT must be between 1 and 65535')
    if not relay_username or not relay_password:
        raise SystemExit('PFIF_SMTP_RELAY_USERNAME and PFIF_SMTP_RELAY_PASSWORD are required when relay is enabled')
    if any(ch in relay_username + relay_password for ch in '\r\n'):
        raise SystemExit('SMTP relay credentials must not contain newline characters')
    if relay_tls_mode not in {'starttls', 'implicit_tls'}:
        raise SystemExit('PFIF_SMTP_RELAY_TLS_MODE must be starttls or implicit_tls')

api_key = env('PFIF_MAILCOW_API_KEY').strip()
if api_key and not re.fullmatch(r'[A-Za-z0-9-]{9,}', api_key):
    raise SystemExit('PFIF_MAILCOW_API_KEY may contain only A-Z, a-z, 0-9 and hyphen, minimum 9 characters')

def yq(v):
    return json.dumps(v)

generated = f"""---
mailcow_hostname: {yq(env('PFIF_MAIL_HOSTNAME'))}
mailcow_domain: {yq(env('PFIF_MAIL_DOMAIN'))}
mailcow_install_path: /opt/mailcow-dockerized
mailcow_git_repository: https://github.com/mailcow/mailcow-dockerized
mailcow_git_version: master
mailcow_timezone: {yq(env('PFIF_TIMEZONE', 'Asia/Karachi'))}
mailcow_skip_lets_encrypt: {str(boolean('PFIF_MAILCOW_SKIP_LETS_ENCRYPT')).lower()}
mailcow_skip_clamd: {str(boolean('PFIF_MAILCOW_SKIP_CLAMD')).lower()}
mailcow_skip_fts: {str(boolean('PFIF_MAILCOW_SKIP_FTS', 'true')).lower()}
mailcow_skip_sogo: {str(boolean('PFIF_MAILCOW_SKIP_SOGO')).lower()}
mailcow_enable_ipv6: {str(boolean('PFIF_MAILCOW_ENABLE_IPV6')).lower()}
mailcow_watchdog_notify_email: {yq(env('PFIF_MAILCOW_WATCHDOG_EMAIL'))}
mailcow_api_key: {yq(api_key)}
mailcow_api_allow_from: {yq(env('PFIF_MAILCOW_API_ALLOW_FROM', '127.0.0.1,172.22.1.1'))}
mailcow_smtp_relay_enabled: {str(relay_enabled).lower()}
mailcow_smtp_relay_host: {yq(relay_host)}
mailcow_smtp_relay_port: {relay_port}
mailcow_smtp_relay_username: {yq(relay_username)}
mailcow_smtp_relay_password: {yq(relay_password)}
mailcow_smtp_relay_tls_mode: {yq(relay_tls_mode)}
mailcow_backup_path: /opt/mailcow-backups
mailcow_backup_retention_days: {integer('PFIF_BACKUP_RETENTION_DAYS', 14)}
mailcow_backup_schedule: {yq(env('PFIF_BACKUP_SCHEDULE', '*-*-* 02:30:00'))}
docker_users:
  - {env('PFIF_ADMIN_USERNAME', 'azureadmin')}
"""
(ansible / 'inventory/group_vars/mailcow/generated.yml').write_text(generated)
for p in [tofu/'terraform.tfvars', tofu/'backend.hcl', ansible/'inventory/group_vars/mailcow/generated.yml']:
    p.chmod(0o600)
PY

info "Generated OpenTofu and Ansible configuration"
info "SSH allowed CIDR(s): $PFIF_EFFECTIVE_SSH_ALLOWED_CIDRS"
