# HamVox

Voice control for AllStarLink and HamVOIP node connections using Alexa,
bridged through Home Assistant and Matter. No skill, no cloud account, and
no port forwarding required for the actual switching.

## Why this project exists

HamVox was inspired by blind and visually impaired ("white stick")
operators, who may not be able to use the Asterisk CLI or navigate visual
tools like AllScan or AllMon. Voice control removes that barrier:
connecting, disconnecting, or switching nodes needs only a spoken command
to Alexa, with no screen, keyboard, or CLI required.

Credit to **G5TOM** and **M7VDX** for the inspiration behind this project.

Hopefully this, or something like it, eventually makes its way into
official builds of ASL3 and HamVOIP, so voice commands can change or
disconnect nodes natively, without a separate Home Assistant/Alexa setup.

73 M3COL (Greg)


## Usage

Saying **"Alexa, turn on NWAG Primary"** runs:

```
rpt cmd 1998 ilink 6                # disconnect all current links
rpt cmd 1998 ilink 3 53573          # connect to NWAG primary, transceive
```

Saying **"Alexa, turn off NWAG Primary"** runs:

```
rpt cmd 1998 ilink 6                # disconnect all current links
```

Only one node can be connected at a time (that's how AllStar/app_rpt works,
not a HamVox limitation). If you say "Alexa, turn on X" while a
*different* node Y is already connected, HamVox refuses the request
(logged to syslog as `hamvox`) and X stays off — Alexa will report it
didn't turn on. Turn Y off first, then turn X on. This check runs live
against Asterisk every time, so it's always correct regardless of what
Home Assistant's dashboard happens to be showing at that moment.

The switches' on/off state does still get double-checked against reality
(not just assumed from the last button pressed), but *not* on a tight
polling loop — that would mean 6+ `sudo asterisk -rx` calls every few
seconds, all day, for a Pi that's otherwise idle. Instead:

- Whenever you say "Alexa, turn on/off X", Home Assistant re-checks X's
  own state immediately after running that command — this happens
  regardless of any polling interval, so the switch you just spoke to is
  always accurate right away.
- A slow background poll (`scan_interval: 120`, i.e. every 2 minutes) is
  only a safety net for the *other* switches, e.g. after switching to a
  different node, or if someone connects to the node from the Asterisk
  CLI directly. For an instant cross-switch refresh instead of waiting up
  to 2 minutes, add the optional automation below.
- The **HamVox Active Node** sensor shows which node (if any) is currently
  connected, for one place to check regardless of switch state.

**Optional: instant refresh across all switches.** Add this to your own
`automations.yaml` (adjust entity IDs if you renamed any switches) to
have every HamVox switch and the active-node sensor recheck itself the
moment *any* of them changes, instead of waiting for the next
`scan_interval` poll:

```yaml
- alias: HamVox - refresh on change
  trigger:
    - platform: state
      entity_id:
        - switch.hamvox_nwag_primary
        - switch.hamvox_nwag_fallback
        - switch.hamvox_east_coast_hub
        - switch.hamvox_free_star
        - switch.hamvox_north_west_multimode
        - switch.hamvox_enhanced_parrot
  action:
    - service: homeassistant.update_entity
      target:
        entity_id:
          - switch.hamvox_nwag_primary
          - switch.hamvox_nwag_fallback
          - switch.hamvox_east_coast_hub
          - switch.hamvox_free_star
          - switch.hamvox_north_west_multimode
          - switch.hamvox_enhanced_parrot
          - sensor.hamvox_active_node
```

This is still purely event-driven (it only ever runs right after one of
the switches changes), not a tighter poll — it just closes the small gap
where a *different* switch's display would otherwise lag behind by up to
`scan_interval`.

## How it works

1. **Home Assistant**, running on the same box as Asterisk, has one
   `command_line` switch per node plus a sensor showing the active node
   (`config/homeassistant/hamvox.yaml`). Each switch/sensor calls
   `scripts/hamvox-asterisk-cmd.sh`, a small input-validated wrapper
   invoked via `sudo`, never Asterisk directly.
2. A **Matter bridge** ([Home Assistant Matter
   Hub](https://github.com/RiDDiX/home-assistant-matter-hub)) exposes
   those switches to any Matter controller.
3. **Alexa** commissions the bridge directly over Matter. No skill, no
   account linking, no cloud dependency for the actual switching.

Earlier versions of this project used [Fauxmo](https://github.com/n8henrie/fauxmo)
to emulate a Belkin WeMo device instead. Amazon changed how Alexa
discovers local WeMo/Hue-style devices in November 2025, now requiring SSL
for anything newly added, which broke that approach for new setups. Matter
is the replacement people have actually gotten working, so HamVox now uses
Home Assistant + Matter instead, and no longer needs Fauxmo at all.

## Requirements / prerequisites

Before installing this, you need:

- **A working ASL3 or HamVOIP node.** This only drives an *existing* node
  connection via the local Asterisk CLI; it doesn't set up AllStar itself.
  Confirm you can connect and disconnect nodes manually with
  `asterisk -rx "rpt cmd <node> ..."` first. See the
  [ASL3 install docs](https://allstarlink.github.io/) or
  [HamVOIP](http://hamvoip.org/).
- **A Raspberry Pi** (or other Linux box) running that node. HamVOIP
  supports Pi 3B/3B+/4 (check current docs for your board). ASL3 supports
  Pi 3, 4, 5, Zero 2 W, and amd64/x86, so a non-Pi Linux box works too.
- **A radio transceiver and interface** connected to and configured with
  your node (e.g. a URIxB/DMK-style USB interface, or a supported HT/mobile
  radio via `chan_simpleusb`/`chan_usbradio`). The wrapper script only
  issues link connect/disconnect commands over the network side of
  AllStar; it doesn't touch radio or audio configuration, so your node
  needs to already be transmitting and receiving correctly.
- **A Matter-capable Amazon device** (not every Echo model supports
  Matter) on the **same LAN** as the Pi. Matter commissioning doesn't cross
  routed networks or the internet.
- **`sudo`/root access** on the Pi, to install Home Assistant, the wrapper
  scripts, and the Matter bridge.
- Root/sudo access to `/usr/sbin/asterisk` on that same machine. This has
  to run directly on the box where Asterisk/`app_rpt` is live; it won't
  work against a remote node over the network.

## Devices configured

| Say "Alexa, turn on ..." | Target node | Notes |
|---|---|---|
| NWAG Primary | 53573 | NWAG primary |
| NWAG Fallback | 47977 | NWAG fallback |
| East Coast Hub | 27339 | East Coast HUB |
| Free Star | 2167 | Free Star |
| North West Multimode | 533411 | NWMG (North West Multimode Grp) |
| Enhanced Parrot | 55553 | Echo test node |

`config/homeassistant/hamvox.yaml` doesn't ship in the repo;
`config/homeassistant/hamvox.yaml.sample` does. The first time you run
`sudo scripts/configure-node.sh` (see Installation below), it copies the
sample to `hamvox.yaml` if that file doesn't exist yet, then replaces the
`MY_NODE` placeholder in every switch with your local node number,
detected from Asterisk/`allstar.env`/`rpt.conf`. Re-run it any time your
local node number changes.

Edit `config/homeassistant/hamvox.yaml` (not the `.sample`) to add,
remove, or rename devices/nodes. It's gitignored, since it holds your own
node numbers; `hamvox.yaml.sample` is the tracked template.

## Repo layout

```
config/homeassistant/hamvox.yaml.sample   Template Home Assistant switches/sensor, copied to hamvox.yaml on first run
config/homeassistant/hamvox.yaml          Your Home Assistant switch/sensor config (gitignored)
scripts/hamvox-asterisk-cmd.sh            Input-validated wrapper, invoked via sudo
scripts/detect-node.sh                    Detects local node number + system flavor
scripts/configure-node.sh                 One-time setup: creates hamvox.yaml, fills in your node number
```

## How it stays safe to run with `sudo`

Home Assistant doesn't call `sudo asterisk -rx "..."` directly. It calls
`sudo /usr/local/bin/hamvox-asterisk-cmd.sh <my_node> <connect|disconnect|status> [<target_node>] [<ilink_num>]`.
The wrapper script only exposes those three operations, rejects anything
that isn't a plain number for `<my_node>`/`<target_node>`/`<ilink_num>`,
and restricts `<ilink_num>` to the three non-permanent connect modes (`2`,
`3`, `8`) — so it can't be used to run an arbitrary shell or Asterisk
command as root, and `sudoers` is scoped to that one script path. It also
refuses to `connect` to a different node while one is already connected
(see "Usage" above), so a bad or overlapping switch press can't silently
knock an existing link off the air.

## HamVOIP vs ASL3

This works unmodified on either. Both are Asterisk + `app_rpt`, and the
`ilink` function numbers this project calls (`6` = disconnect all, `3` =
connect transceive) are the same on both. Note that ilink `3` is a normal
(non-permanent) connect: it won't survive an Asterisk/app_rpt restart on
its own, so a node reboot leaves everything disconnected until you tell
Alexa to reconnect it. That's deliberate here, since these are
user-toggled switches, not always-on links; app_rpt's separate "permanent"
connect (ilink `13`, undone with `11` rather than `6`) isn't used by this
project.

A few things to know when running on ASL3 specifically:

- **Asterisk runs as the `asterisk` user, not root.** This only matters if
  something talks to the Asterisk CLI without elevated privileges. Since
  `hamvox-asterisk-cmd.sh` is invoked via `sudo` (root) either way, no changes are
  needed; root can reach the Asterisk control socket on both platforms.
- **ASL3 also runs on amd64/x86, not just Raspberry Pi.** Nothing here is
  Pi-specific beyond the docs assuming a Pi. Install steps are identical on
  an x86 ASL3 box.
- **Double-check `my_node` in `config/homeassistant/hamvox.yaml`.** Make
  sure it matches the node number actually registered on your ASL3 install
  (portal registration works differently from HamVOIP, so it's easy to
  have a stale number after a migration).
- Everything else (wrapper script, sudoers entry, Home Assistant config)
  is identical between the two.

## Installation

Run these on the same Pi where Asterisk/`app_rpt` is running. `asterisk -rx`
only works against a local Asterisk instance.

### 1. Get the code onto the Pi

```bash
sudo mkdir -p /opt/hamvox
sudo chown "$USER" /opt/hamvox
git clone <your-repo-url> /opt/hamvox
cd /opt/hamvox
```

### 2. Install Home Assistant Core

Follow the [official Linux install docs](https://www.home-assistant.io/installation/linux)
to install Home Assistant Core directly on this box (not a container that
can't reach the local Asterisk CLI, and not Home Assistant OS/Supervised,
which expects to own the whole machine). Those docs have you create a
dedicated `homeassistant` system user; do that before continuing.

### 3. Install the wrapper script

`scripts/detect-node.sh` doesn't need installing system-wide; it's only
ever run locally by `scripts/configure-node.sh` (step 5). Only the wrapper
that Home Assistant calls at runtime needs to live outside the repo:

```bash
sudo cp scripts/hamvox-asterisk-cmd.sh /usr/local/bin/hamvox-asterisk-cmd.sh
sudo chown root:root /usr/local/bin/hamvox-asterisk-cmd.sh
sudo chmod 755 /usr/local/bin/hamvox-asterisk-cmd.sh
```

### 4. Grant the Home Assistant user passwordless sudo for the wrapper only

```bash
sudo visudo -f /etc/sudoers.d/hamvox-asterisk-cmd
```

Add this line, save, and exit:

```
homeassistant ALL=(root) NOPASSWD: /usr/local/bin/hamvox-asterisk-cmd.sh
```

Lock down the permissions on the sudoers snippet itself:

```bash
sudo chmod 440 /etc/sudoers.d/hamvox-asterisk-cmd
```

### 5. Detect and configure your node number

Instead of hand-editing `config/homeassistant/hamvox.yaml`, let the repo
find your node number for you:

```bash
sudo scripts/configure-node.sh
sudo chown "$USER":"$USER" config/homeassistant/hamvox.yaml
```

If `hamvox.yaml` doesn't exist yet, this creates it from
`hamvox.yaml.sample` first. It then runs `detect-node.sh` (checking
`allstar.env`, then `rpt nodes`, then `rpt.conf`, in that order), prints
the detected node number and whether it thinks this is HamVOIP or ASL3,
and replaces the `MY_NODE` placeholder in every switch. Re-run it any
time your node number changes.

### 6. Add the switches to Home Assistant

Either paste the `command_line:` block from
`config/homeassistant/hamvox.yaml` straight into your Home Assistant
`configuration.yaml`, or add a line there to include the file:

```yaml
command_line: !include /opt/hamvox/config/homeassistant/hamvox.yaml
```

(adjust the path if you didn't use `/opt/hamvox`, and drop the leading
`command_line:` key from `hamvox.yaml` itself if you include it this way,
since the include line already provides it).

Restart Home Assistant:

```bash
sudo systemctl restart home-assistant@homeassistant
```

Check the switches appear and toggle correctly from the Home Assistant
dashboard before involving Alexa at all, that's the quickest way to
confirm the wrapper script and sudoers are working.

### 7. Install a Matter bridge and expose the switches

Install [Home Assistant Matter Hub](https://github.com/RiDDiX/home-assistant-matter-hub),
following that project's own install and pairing docs (its packaging and
setup steps change independently of this repo). Once running, use its
dashboard to expose the new HamVox switches.

### 8. Network / firewall notes

Matter needs mDNS for discovery plus its own operational port, both UDP:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 5353 proto udp
sudo ufw allow from 192.168.1.0/24 to any port 5540 proto udp
sudo ufw reload
```

(Replace `192.168.1.0/24` with your own LAN subnet.) If you run
`firewalld` instead:

```bash
sudo firewall-cmd --permanent --add-port=5353/udp
sudo firewall-cmd --permanent --add-port=5540/udp
sudo firewall-cmd --reload
```

Matter and its port assignments are still evolving; check your Matter
bridge's own troubleshooting docs if commissioning doesn't work with just
these two.

### 9. Commission the bridge with Alexa

In the Alexa app: Devices > **+** > Add Device > **Matter**, and follow
the prompts (usually scanning a QR code the Matter bridge's dashboard
gives you).

## Auto-detecting your node number

`scripts/configure-node.sh` (step 5 above) bakes your node number into
`config/homeassistant/hamvox.yaml` once. Detection runs a single time
during setup, and Home Assistant never has to shell out or need extra
sudo access to figure out its own node number at runtime. Re-run the
script any time the node number changes (new SD card, node
re-registration, etc).

Detection logic lives in `scripts/detect-node.sh`: it tries `NODE1` from
`/usr/local/etc/allstar.env` (common on HamVOIP), then falls back to
asking Asterisk directly (`rpt localnodes`), then falls back to reading the
first node stanza out of `/etc/asterisk/rpt.conf`. System flavor (HamVOIP
vs ASL3) is detected too and printed for information; the underlying
`ilink` commands are identical on both, so flavor doesn't change behavior,
it's just handy for diagnostics.

## Verifying node status manually

To confirm connections independent of Alexa/Home Assistant, run the same
kind of status query you'd use directly on the Pi:

```bash
sudo /usr/sbin/asterisk -rx "rpt cmd 1998 status 11 xxx"
```

(Substitute your own node number for `1998`.)

## Troubleshooting

- **Alexa says a device isn't responding**: check Home Assistant's own
  logs for the switch entity, and confirm it toggles correctly from the
  Home Assistant dashboard first, that isolates whether the problem is the
  wrapper script/sudo or the Matter bridge/Alexa side.
- **`sudo: a password is required`**: the sudoers line in step 4 wasn't
  applied to the `homeassistant` user, or the path doesn't exactly match
  `/usr/local/bin/hamvox-asterisk-cmd.sh`.
- **A value in `config/homeassistant/hamvox.yaml` still says `MY_NODE`**:
  `scripts/configure-node.sh` hasn't been run yet, or failed to detect a
  node number, run it again and check its output.
- **Devices don't show up when commissioning in the Alexa app**: confirm
  the Matter bridge and your Echo device are on the same LAN, that UDP
  5353 and 5540 aren't blocked, and check the Matter bridge's own
  connectivity troubleshooting docs.
- **A switch won't turn on / immediately flips back off**: another node is
  probably already connected — check the **HamVox Active Node** sensor, or
  run `journalctl -t hamvox` (or check `/var/log/syslog`) for a "refused"
  line naming which node to disconnect first.

## Customizing

- **Add a node**: add another `- switch:` entry to
  `config/homeassistant/hamvox.yaml`, following the pattern of the
  existing ones, with a new `name`, `unique_id`, and target node number in
  the `command_on`/`command_state` lines. Also add the node number/name
  pair to the `names` map in the `HamVox Active Node` sensor's
  `value_template`, so the sensor shows its name too. No code changes
  needed.
- **Change the ilink mode** (e.g. monitor-only instead of transceive): add
  the ilink number as a 4th argument on the `command_on` line, e.g.
  `... connect 53573 2` for monitor-only. The wrapper only allows `2`
  (monitor-only), `3` (transceive, the default), or `8`
  (local-monitor-only) — the permanent-link variants (`12`/`13`, undone
  with `11` rather than `disconnect`) aren't supported, since this project
  is built around user-toggled, non-permanent links (see "HamVOIP vs
  ASL3").

## License

MIT. See `LICENSE`.
