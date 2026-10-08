#!/bin/bash

# Install the K380 Fn-Lock bar widget for Omarchy.
#
#   ./install.sh           from a source checkout: build the helper, copy the
#                          plugin, install the udev rule, enable the widget.
#   ./install.sh --setup   build the helper and install the udev rule in place;
#                          what the panel's "Finish setup" button runs after
#                          `omarchy plugin add`.

set -euo pipefail

PLUGIN_ID="io.github.sxardas.omarchy-k380-fnlock"
SOURCE_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
RULE_NAME="70-omarchy-k380-fnlock.rules"
RULE_TARGET="/etc/udev/rules.d/$RULE_NAME"

build_helper() {
  if ! command -v make >/dev/null || ! command -v cc >/dev/null; then
    echo "Building the helper needs make and a C compiler: omarchy pkg add base-devel" >&2
    exit 1
  fi
  make -C "$SOURCE_DIR"
}

install_udev_rule() {
  if cmp -s "$SOURCE_DIR/udev/$RULE_NAME" "$RULE_TARGET"; then
    echo "udev rule already installed: $RULE_TARGET"
  else
    echo "Installing udev rule to $RULE_TARGET (needs sudo)"
    sudo install -Dm644 "$SOURCE_DIR/udev/$RULE_NAME" "$RULE_TARGET"
    sudo udevadm control --reload-rules
    # Re-run the rules on hidraw nodes that already exist, so a connected
    # keyboard picks up the seat ACL without reconnecting.
    sudo udevadm trigger --subsystem-match=hidraw --action=change
    sudo udevadm settle
  fi
}

# A copy rather than a symlink: the shell's inotify watcher does not follow
# links, so edits behind one would never hot-reload.
copy_plugin() {
  if [[ $SOURCE_DIR == "$(readlink -f -- "$PLUGIN_DIR" 2>/dev/null)" ]]; then
    echo "Running from $PLUGIN_DIR; nothing to copy"
    return
  fi
  if [[ -d $PLUGIN_DIR/.git ]]; then
    echo "$PLUGIN_DIR is a git checkout managed by 'omarchy plugin'; leaving it alone" >&2
    return
  fi
  # Start clean so files dropped in a newer version do not linger. Settings
  # live in shell.json, not here.
  rm -rf -- "$PLUGIN_DIR"
  mkdir -p "$PLUGIN_DIR"
  cp -r "$SOURCE_DIR"/{manifest.json,src,helper,bin,udev,assets,Makefile,install.sh,uninstall.sh,README.md,LICENSE} "$PLUGIN_DIR"/
  echo "Copied plugin to $PLUGIN_DIR"
}

case "${1:-}" in
  --setup)
    build_helper
    install_udev_rule
    echo "Setup done. The widget picks it up on its next refresh."
    exit 0
    ;;
  "") ;;
  -h | --help)
    sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "unknown option: $1" >&2
    exit 2
    ;;
esac

build_helper
copy_plugin
install_udev_rule

if omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null
  sleep 1
  if ! grep -q "\"$PLUGIN_ID\"" "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
    omarchy plugin enable "$PLUGIN_ID" --before omarchy.bluetooth 2>/dev/null \
      || omarchy plugin enable "$PLUGIN_ID"
  fi
  # Hot reload keeps the loaded QML cached, so only a restart runs the new code.
  omarchy restart shell >/dev/null 2>&1
  echo "Enabled $PLUGIN_ID in the bar and restarted the shell"
else
  echo "omarchy-shell is not running; enable later with: omarchy plugin enable $PLUGIN_ID"
fi
