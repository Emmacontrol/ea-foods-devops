#!/usr/bin/env bash
# Verify both services answer through the public load balancer AND that the
# expected release is the one serving traffic (X-App-Version response header).
#
# Usage: scripts/smoke-test.sh <base-url> <expected-version>
set -euo pipefail

base_url="${1:?usage: smoke-test.sh <base-url> <expected-version>}"
expected="${2:?usage: smoke-test.sh <base-url> <expected-version>}"
attempts="${SMOKE_ATTEMPTS:-10}"

for path in /orders /notify; do
  for attempt in $(seq 1 "${attempts}"); do
    status="" got=""
    if headers="$(curl -sS -o /dev/null -D - --max-time 10 "${base_url}${path}" 2>/dev/null)"; then
      status="$(awk 'NR == 1 { print $2 }' <<<"${headers}")"
      got="$(awk 'tolower($1) == "x-app-version:" { print $2 }' <<<"${headers}" | tr -d '\r')"
    fi
    if [ "${status}" = "200" ] && [ "${got}" = "${expected}" ]; then
      echo "OK   ${path} -> 200, version ${got}"
      continue 2
    fi
    echo "wait ${path}: want 200 + version ${expected}, got HTTP ${status:-no response}, version ${got:-none} (attempt ${attempt}/${attempts})"
    sleep 6
  done
  echo "FAIL ${path} is not serving ${expected}" >&2
  exit 1
done
