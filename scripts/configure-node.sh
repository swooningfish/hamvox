#!/bin/bash
#
# configure-node.sh, one-time setup helper.
#
# On first run, copies config/fauxmo.json.sample to config/fauxmo.json if
# fauxmo.json doesn't exist yet. Either way, it then:
#   1. Sets the AllStarPlugin "path" to the absolute path of
#      plugins/allstar_plugin.py, worked out relative to this script's own
#      location, so it's correct no matter where the repo was cloned to.
#   2. Runs detect-node.sh to find this system's local node number (and
#      flavor, for info), and writes that node number into every device's
#      "my_node" field.
#
# Run this once after cloning, before starting the fauxmo service, and
# re-run it any time the local node number changes (new SD card, node
# re-registration, etc). Safe to re-run: it never touches your DEVICES
# entries except for "my_node".
#
# Usage: sudo scripts/configure-node.sh [path/to/fauxmo.json]
#
# Needs sudo because detect-node.sh talks to the Asterisk CLI, which
# requires root (or, on ASL3, membership in the asterisk group).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="${1:-$REPO_ROOT/config/fauxmo.json}"
SAMPLE_FILE="$REPO_ROOT/config/fauxmo.json.sample"
PLUGIN_PATH="$REPO_ROOT/plugins/allstar_plugin.py"

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

if [ ! -f "$PLUGIN_PATH" ]; then
    echo "Warning: expected plugin at $PLUGIN_PATH but it doesn't exist." >&2
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

python3 - "$CONFIG_FILE" "$NODE" "$PLUGIN_PATH" <<'PYEOF'
import json
import sys

config_path, node, plugin_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(config_path) as f:
    config = json.load(f)

plugin = config["PLUGINS"]["AllStarPlugin"]
plugin["path"] = plugin_path

devices = plugin["DEVICES"]
for device in devices:
    device["my_node"] = node

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print(f"Set plugin path -> {plugin_path}")
print(f"Updated {len(devices)} device(s) in {config_path} -> my_node={node}")
PYEOF

echo "Detected system flavor: ${FLAVOR} (informational, HamVOIP and AllStarLink/ASL3 use identical ilink command syntax)"
echo
echo "If this was run with sudo, fix ownership of the config file back to your user, e.g.:"
echo "  sudo chown \$(logname):\$(logname) \"$CONFIG_FILE\""
echo
echo "Then restart the service to pick up the change:"
echo "  sudo systemctl restart fauxmo"
