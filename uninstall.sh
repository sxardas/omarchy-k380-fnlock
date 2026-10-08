#!/bin/bash

# Remove exactly what install.sh puts on the system:
#
#   - the bar entry in ~/.config/omarchy/shell.json, with the settings the
#     widget saved on it
#   - ~/.config/omarchy/plugins/omarchy-k380-fnlock
#   - /etc/udev/rules.d/70-omarchy-k380-fnlock.rules (asks for sudo) and the ACL it
#     granted on the keyboard's hidraw node
#
# Before removing the helper, the keyboard's Fn lock is put back to the
# factory Media keys; skip that with --keep-mode.
#
# A source checkout outside ~/.config/omarchy/plugins is left alone.

set -euo pipefail

PLUGIN_ID="io.github.sxardas.omarchy-k380-fnlock"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
RULE_TARGET="/etc/udev/rules.d/70-omarchy-k380-fnlock.rules"

keep_mode=0
case "${1:-}" in
  --keep-mode) keep_mode=1 ;;
  "") ;;
  -h | --help)
    echo "Usage: $0 [--keep-mode]"
    exit 0
    ;;
  *)
    echo "unknown option: $1" >&2
    exit 2
    ;;
esac

shell_running() {
  omarchy-shell shell ping >/dev/null 2>&1
}

# Needs the helper and the udev ACL, so it goes before either is removed.
reset_keyboard() {
  (( keep_mode )) && return
  local helper
  for helper in "$PLUGIN_DIR/bin/omarchy-k380-fnlock" "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/bin/omarchy-k380-fnlock"; do
    if [[ -x $helper ]]; then
      if "$helper" set media >/dev/null 2>&1; then
        echo "Keyboard Fn lock reset to Media keys"
      else
        echo "Keyboard not reachable; its Fn lock resets on its own at the next power cycle"
      fi
      return
    fi
  done
}

remove_bar_entry() {
  if shell_running; then
    omarchy-shell shell setPluginEnabled "$PLUGIN_ID" false >/dev/null 2>&1 || true
  fi

  # For a shell that is not running: drop the entry from the file directly.
  [[ -f $SHELL_CONFIG ]] || return 0
  local cleaned
  cleaned=$(jq --arg id "$PLUGIN_ID" '
    if .bar.layout then .bar.layout |= map_values(map(select(.id != $id))) else . end
  ' "$SHELL_CONFIG")
  if [[ $cleaned != "$(jq . "$SHELL_CONFIG")" ]]; then
    printf '%s\n' "$cleaned" >"$SHELL_CONFIG"
  fi
  echo "Removed $PLUGIN_ID from $SHELL_CONFIG"
}

remove_plugin_files() {
  if [[ -e $PLUGIN_DIR || -L $PLUGIN_DIR ]]; then
    rm -rf -- "$PLUGIN_DIR"
    echo "Deleted $PLUGIN_DIR"
  else
    echo "No plugin at $PLUGIN_DIR"
  fi
  if shell_running; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
}

remove_udev_rule() {
  if [[ ! -e $RULE_TARGET ]]; then
    echo "No udev rule at $RULE_TARGET"
    return
  fi
  echo "Removing $RULE_TARGET (needs sudo)"
  sudo rm -f -- "$RULE_TARGET"
  sudo udevadm control --reload-rules
  # Re-run the rules so the keyboard's hidraw node loses the seat ACL now
  # rather than at the next reconnect.
  sudo udevadm trigger --subsystem-match=hidraw --action=change
  sudo udevadm settle
}

reset_keyboard
remove_bar_entry
remove_plugin_files
remove_udev_rule

echo "K380 Fn-Lock is removed"
