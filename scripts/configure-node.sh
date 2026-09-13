#!/bin/bash
#
# configure-node.sh — one-time setup helper.
#
# Runs detect-node.sh to find this system's local node number (and flavor,
# for info), then writes that node number into every device's "my_node"
# field in config/fauxmo.json. Run this once after cloning, before starting
# the fauxmo service — and re-run it any time the local node number changes
# (new SD card, node re-registration, etc).
#
# Usage: sudo scripts/configure-node.sh [path/to/fauxmo.json]
#
# Needs sudo because detect-node.sh talks to the Asterisk CLI, which
# requires root (or, on ASL3, membership in the asterisk group).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/../config/fauxmo.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
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

python3 - "$CONFIG_FILE" "$NODE" <<'PYEOF'
import json
import sys

config_path, node = sys.argv[1], sys.argv[2]

with open(config_path) as f:
    config = json.load(f)

devices = config["PLUGINS"]["AllStarPlugin"]["DEVICES"]
for device in devices:
    device["my_node"] = node

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print(f"Updated {len(devices)} device(s) in {config_path} -> my_node={node}")
PYEOF

echo "Detected system flavor: ${FLAVOR} (informational — HamVOIP and AllStarLink/ASL3 use identical ilink command syntax)"
echo
echo "If this was run with sudo, fix ownership of the config file back to your user, e.g.:"
echo "  sudo chown \$(logname):\$(logname) \"$CONFIG_FILE\""
echo
echo "Then restart the service to pick up the change:"
echo "  sudo systemctl restart fauxmo"
