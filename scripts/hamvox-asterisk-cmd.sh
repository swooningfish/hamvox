#!/bin/bash
#
# hamvox-asterisk-cmd.sh, restricted wrapper around `asterisk -rx "rpt ..."`.
#
# This exists so sudoers can grant NOPASSWD access to exactly this script
# (see README.md) instead of to `asterisk` itself. It exposes exactly three
# operations -- connect, disconnect, status -- and validates every argument,
# so it cannot be used to inject arbitrary Asterisk CLI commands.
#
# Only one node can be connected at a time. "connect" checks what's
# currently connected first and refuses (logging why, via syslog) if a
# *different* node is already up, rather than silently dropping it. Turn
# the active node off before switching to another.
#
# Usage:
#   hamvox-asterisk-cmd.sh <my_node> connect <target_node> [<ilink_num>]
#   hamvox-asterisk-cmd.sh <my_node> disconnect
#   hamvox-asterisk-cmd.sh <my_node> status [<target_node>]
#
# <ilink_num> (connect only) defaults to 3 and must be one of the
# non-permanent "connect specified link" modes: 2 (monitor only), 3
# (transceive), 8 (local monitor only).
#
# "status" with a target_node exits 0 if that node is currently connected
# and 1 otherwise, matching Home Assistant's command_line switch
# command_state convention (used to poll each switch's real state).
# "status" with no target_node prints the currently connected node
# number(s) (comma-separated, empty if none), for use as a command_line
# sensor showing which node (if any) is active.
#
# Examples:
#   hamvox-asterisk-cmd.sh 1998 connect 53573       # connect to 53573, transceive
#   hamvox-asterisk-cmd.sh 1998 connect 53573 2     # connect to 53573, monitor only
#   hamvox-asterisk-cmd.sh 1998 disconnect          # disconnect all links
#   hamvox-asterisk-cmd.sh 1998 status 53573        # exit 0 if 53573 is connected
#   hamvox-asterisk-cmd.sh 1998 status              # print connected node(s)

set -euo pipefail

# Overridable via environment for local testing only; sudo resets the
# environment by default so this can't be redirected in production.
: "${ASTERISK_BIN:=/usr/sbin/asterisk}"

usage() {
    echo "Usage: $0 <my_node> connect <target_node> [<ilink_num>]" >&2
    echo "       $0 <my_node> disconnect" >&2
    echo "       $0 <my_node> status [<target_node>]" >&2
    exit 1
}

is_numeric() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

[[ $# -ge 2 ]] || usage

MY_NODE="$1"
ACTION="$2"
TARGET="${3:-}"

is_numeric "$MY_NODE" || { echo "Invalid my_node: $MY_NODE" >&2; exit 1; }

# Node numbers currently connected to MY_NODE, one per line (empty if none).
connected_nodes() {
    "$ASTERISK_BIN" -rx "rpt nodes ${MY_NODE}" 2>/dev/null \
        | tr ',' '\n' | grep -oE '[0-9]+' || true
}

case "$ACTION" in
    connect)
        [[ -n "$TARGET" ]] || usage
        is_numeric "$TARGET" || { echo "Invalid target_node: $TARGET" >&2; exit 1; }
        ILINK="${4:-3}"
        is_numeric "$ILINK" || { echo "Invalid ilink: $ILINK" >&2; exit 1; }
        case "$ILINK" in
            2|3|8) ;;
            *) echo "Invalid ilink for connect: $ILINK (must be 2, 3, or 8)" >&2; exit 1 ;;
        esac

        # Refuse to switch away from a different node that's already
        # connected; the caller (Home Assistant) must disconnect it first.
        # A node already connected to exactly TARGET is left alone (no-op
        # reconnect below), so turning "on" an already-on switch is safe.
        CURRENT="$(connected_nodes)"
        OTHER="$(grep -vx "$TARGET" <<<"$CURRENT" | grep -v '^$' || true)"
        if [[ -n "$OTHER" ]]; then
            OTHER_CSV="$(tr '\n' ',' <<<"$OTHER" | sed 's/,$//')"
            logger -t hamvox "refused: ${MY_NODE} -> ${TARGET} (already connected to ${OTHER_CSV}; disconnect it first)" || true
            echo "Node ${MY_NODE} is already connected to ${OTHER_CSV}; disconnect it before connecting to ${TARGET}." >&2
            exit 1
        fi

        logger -t hamvox "connecting ${MY_NODE} -> ${TARGET} (ilink ${ILINK})" || true
        "$ASTERISK_BIN" -rx "rpt cmd ${MY_NODE} ilink 6" >/dev/null
        exec "$ASTERISK_BIN" -rx "rpt cmd ${MY_NODE} ilink ${ILINK} ${TARGET}"
        ;;
    disconnect)
        logger -t hamvox "disconnecting all links on ${MY_NODE}" || true
        exec "$ASTERISK_BIN" -rx "rpt cmd ${MY_NODE} ilink 6"
        ;;
    status)
        if [[ -n "$TARGET" ]]; then
            is_numeric "$TARGET" || { echo "Invalid target_node: $TARGET" >&2; exit 1; }
            grep -qx "$TARGET" <<<"$(connected_nodes)"
        else
            tr '\n' ',' <<<"$(connected_nodes)" | sed 's/,$//'
            echo
        fi
        ;;
    *)
        usage
        ;;
esac
