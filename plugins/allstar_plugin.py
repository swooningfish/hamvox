"""
Fauxmo plugin: control AllStarLink / HamVOIP node connections from Alexa.

Each Fauxmo "device" maps to one target node. Saying "Alexa, turn on <name>"
disconnects all current links on the local node and connects (permanent /
transceive) to the configured target node. "Alexa, turn off <name>"
disconnects all links.

Under the hood this shells out to the Asterisk CLI via a small, input
validated wrapper script (scripts/allstar-cmd.sh) instead of building the
`asterisk -rx "..."` string directly, so a bad config value can't turn into
an arbitrary command passed to sudo. See README.md for the sudoers setup
this depends on.
"""

from __future__ import annotations

import shlex
import subprocess

from fauxmo.plugins import FauxmoPlugin

# AllStar/app_rpt "ilink" function numbers used by this plugin.
ILINK_DISCONNECT_ONE = "1"
ILINK_CONNECT_TRANSCEIVE_PERMANENT = "3"
ILINK_DISCONNECT_ALL = "6"

# Cached across device instances so "my_node": "auto" in the config doesn't
# trigger a separate detection call (and separate sudo prompt/log line) per
# device at Fauxmo startup.
_detected_node_cache: str | None = None


class AllStarPlugin(FauxmoPlugin):
    """Connects/disconnects an AllStar node in response to Alexa on/off."""

    def __init__(
        self,
        *,
        name: str,
        port: int,
        my_node: str,
        target_node: str,
        wrapper_path: str = "/usr/local/bin/allstar-cmd.sh",
        detect_path: str = "/usr/local/bin/allstar-detect-node.sh",
        use_sudo: bool = True,
        timeout: int = 10,
        **kwargs,
    ) -> None:
        if not str(target_node).isdigit():
            raise ValueError(f"target_node must be numeric, got {target_node!r}")

        self.wrapper_path = wrapper_path
        self.detect_path = detect_path
        self.use_sudo = use_sudo
        self.timeout = timeout
        self.target_node = str(target_node)

        # "my_node" can be a literal node number (recommended — see
        # scripts/configure-node.sh, which writes this automatically), or
        # the literal string "auto" to re-detect it from this machine every
        # time Fauxmo starts. Auto mode requires the detect script to also
        # be in sudoers (see README) and adds a small amount of startup
        # latency; most setups are better served by running
        # configure-node.sh once and leaving a plain number here.
        if str(my_node).strip().lower() == "auto":
            self.my_node = self._detect_my_node()
        elif str(my_node).isdigit():
            self.my_node = str(my_node)
        else:
            raise ValueError(
                f"my_node must be numeric or 'auto', got {my_node!r}"
            )

        super().__init__(name=name, port=port)

    def _detect_my_node(self) -> str:
        global _detected_node_cache
        if _detected_node_cache is not None:
            return _detected_node_cache

        cmd: list[str] = []
        if self.use_sudo:
            cmd.append("sudo")
        cmd.append(self.detect_path)

        try:
            result = subprocess.run(
                cmd,
                check=True,
                timeout=self.timeout,
                capture_output=True,
                text=True,
            )
        except (
            subprocess.CalledProcessError,
            subprocess.TimeoutExpired,
            FileNotFoundError,
        ) as exc:
            raise RuntimeError(
                "[AllStarPlugin] node auto-detection failed — set my_node "
                f"explicitly in config/fauxmo.json instead. Error: {exc}"
            ) from exc

        node = None
        for line in result.stdout.splitlines():
            if line.startswith("NODE="):
                node = line.split("=", 1)[1].strip()
                break

        if not node or not node.isdigit():
            raise RuntimeError(
                "[AllStarPlugin] node auto-detection returned no usable "
                f"node number. Output was: {result.stdout!r}"
            )

        print(f"[AllStarPlugin] auto-detected local node: {node}")
        _detected_node_cache = node
        return node

    def _run(self, ilink: str, target: str | None = None) -> bool:
        cmd: list[str] = []
        if self.use_sudo:
            cmd.append("sudo")
        cmd += [self.wrapper_path, self.my_node, ilink]
        if target is not None:
            cmd.append(target)

        try:
            result = subprocess.run(
                cmd,
                check=True,
                timeout=self.timeout,
                capture_output=True,
                text=True,
            )
            if result.stdout:
                print(f"[AllStarPlugin:{self.name}] {result.stdout.strip()}")
            return True
        except subprocess.CalledProcessError as exc:
            print(
                f"[AllStarPlugin:{self.name}] command failed "
                f"({' '.join(shlex.quote(c) for c in cmd)}): {exc.stderr}"
            )
            return False
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            print(f"[AllStarPlugin:{self.name}] command error: {exc}")
            return False

    def on(self) -> bool:
        """Disconnect all current links, then connect to the target node."""
        disconnected = self._run(ILINK_DISCONNECT_ALL)
        connected = self._run(
            ILINK_CONNECT_TRANSCEIVE_PERMANENT, self.target_node
        )
        return disconnected and connected

    def off(self) -> bool:
        """Disconnect all current links."""
        return self._run(ILINK_DISCONNECT_ALL)

    def get_state(self) -> str:
        # Querying real link status would mean parsing `rpt cmd <node> status`
        # output, which is fragile to do reliably here. Fauxmo just needs a
        # value; Alexa treats "unknown" as an unconfirmed but valid state.
        return "unknown"
