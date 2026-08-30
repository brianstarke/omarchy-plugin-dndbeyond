#!/usr/bin/env bash
# Lint the plugin QML with full import resolution.
#
# This Qt build's qmllint segfaults (exit 255) on two legal patterns when -I
# paths are given (first-party omarchy plugins crash it the same way):
#   1. `function f(): void` return annotations
#   2. IpcHandler blocks whose functions call the Panel root's open/close/
#      toggle methods
# Workaround: strip both into temp copies and lint those. IPC handler
# correctness is verified at runtime via omarchy-shell calls instead.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SHELL_QML=/usr/share/omarchy/shell
QT_QML=/usr/lib/qt6/qml

fail=0
for f in Panel.qml Service.qml; do
  tmp=$(mktemp -p . --suffix=.qml)
  F="$f" OUT="$tmp" python3 - <<'EOF'
import os, re
src = open(os.environ["F"]).read()
src = re.sub(r"\(\): void \{", ") {", src)
# drop IpcHandler blocks (brace-balanced)
while True:
    m = re.search(r"(?m)^  IpcHandler \{", src)
    if not m:
        break
    i = src.index("{", m.start())
    depth, j = 0, i
    while True:
        if src[j] == "{": depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0: break
        j += 1
    src = src[:m.start()] + src[j+1:]
open(os.environ["OUT"], "w").write(src)
EOF
  if qmllint -I . -I "$SHELL_QML" -I "$QT_QML" "$tmp"; then
    echo "ok   $f"
  else
    echo "FAIL $f"
    fail=1
  fi
  rm -f "$tmp"
done
exit $fail
