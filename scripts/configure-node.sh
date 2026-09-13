#!/bin/bash
#
# configure-node.sh, one-time setup helper.
#
# On first run, copies config/homeassistant/hamvox.yaml.sample to
# config/homeassistant/hamvox.yaml if it doesn't exist yet. Either way, it
# then runs detect-node.sh to find this system's local node number (and
# flavor, for info), and replaces the MY_NODE placeholder in every switch
# with that node number.
#
# Run this once after cloning, before adding the switches to Home
# Assistant, and re-run it any time the local node number changes (new SD
# card, node re-registration, etc). Safe to re-run: it never touches your
# switch entries except for the node number.
#
# Usage: sudo scripts/configure-node.sh [path/to/hamvox.yaml]
#
# Needs sudo because detect-node.sh talks to the Asterisk CLI, which
# requires root (or, on ASL3, membership in the asterisk group).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="${1:-$REPO_ROOT/config/homeassistant/hamvox.yaml}"
SAMPLE_FILE="$REPO_ROOT/config/homeassistant/hamvox.yaml.sample"

if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$SAMPLE_FILE" ]; then
        echo "No config found at $CONFIG_FILE, copying $SAMPLE_FILE"
        cp "$SAMPLE_FILE" "$CONFIG_FILE"
    else
        echo "Config file not found: $CONFIG_FILE" >&2
        echo "Sample config also not found: $SAMPLE_FILE" >&2
        exit 1
    fi
fi

echo "Detecting local node number and system flavor..."
DETECT_OUTPUT="$("$SCRIPT_DIR/detect-node.sh")"
echo "$DETECT_OUTPUT"

NODE="$(printf '%s\n' "$DETECT_OUTPUT" | awk -F= '/^NODE=/{print $2}')"
FLAVOR="$(printf '%s\n' "$DETECT_OUTPUT" | awk -F= '/^FLAVOR=/{print $2}')"

if [ -z "$NODE" ]; then
    echo "Could not parse a detected node number; aborting." >&2
    exit 1
fi

sed -i "s/MY_NODE/$NODE/g" "$CONFIG_FILE"
echo "Updated $CONFIG_FILE -> MY_NODE=$NODE"

echo "Detected system flavor: ${FLAVOR} (informational, HamVOIP and AllStarLink/ASL3 use identical ilink command syntax)"
echo
echo "If this was run with sudo, fix ownership of the config file back to your user, e.g.:"
echo "  sudo chown \$(logname):\$(logname) \"$CONFIG_FILE\""
echo
echo "Then restart Home Assistant to pick up the change:"
echo "  sudo systemctl restart home-assistant@homeassistant"
