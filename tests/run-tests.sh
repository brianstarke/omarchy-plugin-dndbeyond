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

W=tests/fixture-warlock2024.json
check $W '.sheet.hp.max' 15 "2024 warlock: CON excluded from baseHitPoints -> add CON x level"
check $W '.sheet.hp.current' 8 "2024 warlock: current HP"
check $W '[.sheet.spells[] | select(.name=="Eldritch Mockery")][0].attackSave' "WIS save DC 13" "save spell carries character DC"
check $W '[.sheet.spells[] | select(.name=="Eldritch Mockery")][0].damage[0].dice' "1d4" "spell damage dice extracted"
check $W '[.sheet.spellSlots[] | select(.pact==true)] | length' 1 "warlock: pact slot row from table"
check $W '.sheet.spellSlots[0].max' 2 "warlock 2: pact max 2"
check $W '.sheet.spellSlots[0].used' 1 "warlock: pact used from payload"

B=tests/fixture-fullcaster.json
check $B '[.sheet.spellSlots[] | .max] | join(",")' "4,2" "bard 3: slots derived from full-caster table"
check $B '.sheet.spellSlots[0].used' 1 "bard: used counts from payload"

if [[ $failures -gt 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
