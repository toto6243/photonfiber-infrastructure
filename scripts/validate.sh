#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

best_effort=false
[[ "${1:-}" == "--best-effort" ]] && best_effort=true

hostname="$PFIF_MAIL_HOSTNAME"
public_ip="$(tofu_output_raw public_ip_address 2>/dev/null || true)"
[[ -n "$public_ip" ]] || die "Infrastructure outputs unavailable"

failures=0
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; failures=$((failures+1)); }

resolved="$(python3 - "$hostname" <<'PY' 2>/dev/null || true
import socket, sys
try:
    print('\n'.join(sorted({x[4][0] for x in socket.getaddrinfo(sys.argv[1], 443, socket.AF_INET)})))
except OSError:
    pass
PY
)"
if grep -Fxq "$public_ip" <<<"$resolved"; then
  pass "$hostname resolves to $public_ip"
else
  fail "$hostname does not resolve to $public_ip"
  if $best_effort; then
    warn "Skipping remaining public checks until forward DNS is ready. Run ./pfif validate later."
    exit 0
  fi
fi

check_port() {
  local port="$1" label="$2"
  if python3 - "$hostname" "$port" <<'PY' >/dev/null 2>&1
import socket, sys
with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=8):
    pass
PY
  then pass "$label TCP/$port is reachable"; else fail "$label TCP/$port is not reachable"; fi
}

for entry in '22 SSH' '25 SMTP' '80 HTTP' '443 HTTPS' '587 Submission' '993 IMAPS'; do
  read -r port label <<<"$entry"
  check_port "$port" "$label"
done

if curl -fsSIk --max-time 15 "https://$hostname/" | head -1 | grep -Eq 'HTTP/.* (200|301|302|403)'; then
  pass "Mailcow HTTPS responds"
else
  fail "Mailcow HTTPS did not return an expected status"
fi

smtp_banner="$(python3 - "$hostname" <<'PY' 2>/dev/null || true
import socket, sys
with socket.create_connection((sys.argv[1], 25), timeout=10) as s:
    print(s.recv(512).decode(errors='replace').strip())
PY
)"
if grep -qiE '^220[- ].*ESMTP' <<<"$smtp_banner"; then pass "SMTP banner: $smtp_banner"; else fail "Unexpected SMTP banner: ${smtp_banner:-none}"; fi

ptr="$(python3 - "$public_ip" <<'PY' 2>/dev/null || true
import socket, sys
try: print(socket.gethostbyaddr(sys.argv[1])[0])
except OSError: pass
PY
)"
if [[ "$ptr" == "$hostname" || "$ptr" == "$hostname." ]]; then pass "PTR points to $hostname"; else fail "PTR is '${ptr:-missing}', expected $hostname"; fi

if (( failures > 0 )); then
  warn "$failures validation check(s) failed. DNS, TLS and PTR propagation can take time."
  $best_effort && exit 0
  exit 1
fi
info "All validation checks passed"
