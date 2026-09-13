#!/bin/bash
#
# hamvox-asterisk-cmd.sh, restricted wrapper around `asterisk -rx "rpt cmd ..."`.
#
# This exists so sudoers can grant NOPASSWD access to exactly this script
# (see README.md) instead of to `asterisk` itself. It only accepts numeric
# node/ilink arguments, so it cannot be used to inject arbitrary Asterisk
# CLI commands.
#
# Usage:
#   hamvox-asterisk-cmd.sh <my_node> <ilink_num> [<target_node>]
#
# Examples:
#   hamvox-asterisk-cmd.sh 1998 6            # disconnect all links
#   hamvox-asterisk-cmd.sh 1998 3 53573      # connect to node 53573 (transceive, permanent)

set -euo pipefail

ASTERISK_BIN="/usr/sbin/asterisk"

usage() {
    echo "Usage: $0 <my_node> <ilink_num> [<target_node>]" >&2
    exit 1
}

[[ $# -eq 2 || $# -eq 3 ]] || usage

MY_NODE="$1"
ILINK="$2"
TARGET="${3:-}"

is_numeric() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_numeric "$MY_NODE" || { echo "Invalid my_node: $MY_NODE" >&2; exit 1; }
is_numeric "$ILINK" || { echo "Invalid ilink: $ILINK" >&2; exit 1; }

if [[ -n "$TARGET" ]]; then
    is_numeric "$TARGET" || { echo "Invalid target_node: $TARGET" >&2; exit 1; }
    RPT_CMD="rpt cmd ${MY_NODE} ilink ${ILINK} ${TARGET}"
else
    RPT_CMD="rpt cmd ${MY_NODE} ilink ${ILINK}"
fi

exec "$ASTERISK_BIN" -rx "$RPT_CMD"
