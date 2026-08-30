#!/usr/bin/env bash
# Offline transform checks: run the helper over the fixture payloads and
# assert key derived values. No D&D Beyond access needed.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
failures=0

check() { # check <fixture> <jq filter> <expected> <label>
  local actual
  actual=$(./omarchy-dndbeyond-fetch _parse < "$1" | jq -r "$2")
  if [[ "$actual" == "$3" ]]; then
    echo "ok   $4"
  else
    echo "FAIL $4 — want $3, got $actual"
    failures=$((failures + 1))
  fi
}

F=tests/fixture-character.json
check $F '.sheet.hp.max' 48 "rolled-HP fixture: base kept as-is"
check $F '.sheet.hp.current' 37 "rolled-HP fixture: current = max - removed"
check $F '.sheet.ac' 20 "fixture AC: studded + DEX + shield + item"
check $F '.sheet.abilities[1].score' 20 "fixture DEX: base+bonus+mod"

V=tests/fixture-vlix.json
check $V '.sheet.hp.max' 15 "Vlix: CON excluded from baseHitPoints -> add CON x level"
check $V '.sheet.hp.current' 8 "Vlix: current HP"

if [[ $failures -gt 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
