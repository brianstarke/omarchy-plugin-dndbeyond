#!/usr/bin/env bash
# Remove the widget from the user plugin directory. Auth config is kept;
# delete it by hand if you want the cookie gone too:
#   rm -rf ~/.config/omarchy-dndbeyond
set -euo pipefail

PLUGIN_ID="brianstarke.dndbeyond"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"

if [[ -L "$PLUGIN_DIR" || -d "$PLUGIN_DIR" ]]; then
  rm -rf "$PLUGIN_DIR"
  echo "Removed $PLUGIN_DIR"
else
  echo "Nothing installed at $PLUGIN_DIR"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi
