#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

[[ $# -eq 1 ]] || die "Usage: $0 /path/to/backup"
source_path="$1"
[[ -e "$source_path" ]] || die "Backup path not found: $source_path"
source_path="$(expand_path "$source_path")"

public_ip="$(tofu_output_raw public_ip_address)"
admin_user="$(tofu_output_raw admin_username)"
private_key="$(expand_path "$PFIF_SSH_PRIVATE_KEY_PATH")"
remote_archive=""
tmp_archive=""

cleanup() {
  [[ -n "$tmp_archive" && -f "$tmp_archive" ]] && rm -f "$tmp_archive"
}
trap cleanup EXIT

if [[ -d "$source_path" ]]; then
  tmp_archive="$(mktemp -t pfif-restore.XXXXXX.tar.gz)"
  parent="$(dirname "$source_path")"
  base="$(basename "$source_path")"
  tar -C "$parent" -czf "$tmp_archive" "$base"
  upload_path="$tmp_archive"
  remote_archive="/tmp/pfif-restore-$(date +%s).tar.gz"
else
  upload_path="$source_path"
  case "$upload_path" in
    *.tar.gz) remote_archive="/tmp/pfif-restore-$(date +%s).tar.gz" ;;
    *.tgz) remote_archive="/tmp/pfif-restore-$(date +%s).tgz" ;;
    *.tar.zst) remote_archive="/tmp/pfif-restore-$(date +%s).tar.zst" ;;
    *.tzst) remote_archive="/tmp/pfif-restore-$(date +%s).tzst" ;;
    *) die "Restore input must be a directory or .tar.gz/.tar.zst archive" ;;
  esac
fi

info "Uploading restore source to $public_ip"
scp -i "$private_key" -o StrictHostKeyChecking=accept-new "$upload_path" "$admin_user@$public_ip:$remote_archive"

info "Starting interactive Mailcow restore"
ssh -tt -i "$private_key" -o StrictHostKeyChecking=accept-new "$admin_user@$public_ip" \
  "sudo /usr/local/sbin/pfif-mailcow-restore '$remote_archive'; rc=\$?; rm -f '$remote_archive'; exit \$rc"
