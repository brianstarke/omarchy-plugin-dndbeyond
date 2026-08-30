#!/usr/bin/env bash
# Install the D&D Beyond widget into the user plugin directory and seed the
# auth config. Re-running is safe: the plugin directory is re-linked, an
# existing config is left untouched.
set -euo pipefail

PLUGIN_ID="brianstarke.dndbeyond"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-dndbeyond"

mkdir -p "$(dirname "$PLUGIN_DIR")" "$CONFIG_DIR"
ln -sfn "$SRC_DIR" "$PLUGIN_DIR"
chmod +x "$SRC_DIR/omarchy-dndbeyond-fetch"

if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
  umask 077
  printf '{\n  "cobaltSession": "PASTE_COBALT_SESSION_COOKIE_HERE"\n}\n' > "$CONFIG_DIR/config.json"
  echo "Seeded $CONFIG_DIR/config.json — paste your CobaltSession cookie into it."
else
  echo "Kept existing $CONFIG_DIR/config.json"
fi

chmod 600 "$CONFIG_DIR/config.json"

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

echo "Installed $PLUGIN_ID -> $PLUGIN_DIR"
echo "Next: edit $CONFIG_DIR/config.json, then verify with:"
echo "  $PLUGIN_DIR/omarchy-dndbeyond-fetch auth-check"
