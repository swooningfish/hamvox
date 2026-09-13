#!/bin/bash
#
# detect-node.sh, determine the local AllStar/HamVOIP node number and
# report whether this box is running HamVOIP or AllStarLink (ASL3).
#
# Detection logic adapted from:
# https://gist.github.com/swooningfish/9abcd06f98a9aa6b675a51c895a67d9e
#
# Must run with access to the Asterisk CLI (root, or via sudo). Even
# read-only `asterisk -rx` queries go through the same control socket as
# the commands that change link state, and on ASL3 that socket is owned
# by the `asterisk` user rather than root.
#
# Output (stdout), one KEY=VALUE per line:
#   NODE=<digits>
#   FLAVOR=HamVOIP|AllStarLink
#
# Usage: detect-node.sh   (no arguments)

set -uo pipefail

ASTERISK="/usr/sbin/asterisk"

# ---------------------------------------------------------------------------
# 1. Node discovery
# ---------------------------------------------------------------------------
NODE=""

# HamVOIP conventionally exposes the configured node(s) here.
if [ -f /usr/local/etc/allstar.env ]; then
    # shellcheck disable=SC1091
    source /usr/local/etc/allstar.env
    NODE="${NODE1:-}"
fi

# Fall back to asking Asterisk directly for the first node it knows about.
if [ -z "$NODE" ]; then
    NODE=$("$ASTERISK" -rx "rpt nodes" 2>/dev/null | awk '/^Node/ {print $2; exit}')
fi

# Last resort: read the first node stanza out of rpt.conf directly.
if [ -z "$NODE" ] && [ -f /etc/asterisk/rpt.conf ]; then
    NODE=$(grep -E '^[[:space:]]*\[([0-9]+)' /etc/asterisk/rpt.conf \
        | head -n 1 | tr -d '[]() \t')
fi

# Strip anything trailing after the digits (e.g. "(node-main)").
NODE="${NODE%%(*}"
NODE="$(printf '%s' "$NODE" | tr -cd '0-9')"

if [ -z "$NODE" ]; then
    echo "ERROR: could not determine local node number automatically." >&2
    echo "Set NODE1 in /usr/local/etc/allstar.env, or set the node number" >&2
    echo "manually in config/homeassistant/hamvox.yaml instead of using" >&2
    echo "auto-detection." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. System flavor detection
# ---------------------------------------------------------------------------
# Informational: the ilink command syntax this project relies on (ilink 6 /
# ilink 3) is identical on HamVOIP and AllStarLink/ASL3, so this doesn't
# currently change any behavior. It's reported for logging/diagnostics and
# so any future flavor-specific handling has somewhere to hook in.
FLAVOR="AllStarLink"
if [ -f /etc/hamvoip_release ] || "$ASTERISK" -rx "core show version" 2>/dev/null | grep -qi "hamvoip"; then
    FLAVOR="HamVOIP"
fi

echo "NODE=${NODE}"
echo "FLAVOR=${FLAVOR}"
