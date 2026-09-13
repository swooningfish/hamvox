# HamVox

Voice control for AllStarLink and HamVOIP node connections using Alexa.

Built on [Fauxmo](https://github.com/n8henrie/fauxmo), which emulates Belkin
WeMo devices that Alexa can discover and switch "on"/"off". No skill, no
cloud account, and no internet dependency for the actual switching.

## Why this project exists

HamVox was inspired by blind and visually impaired ("white stick")
operators, who may not be able to use the Asterisk CLI or navigate visual
tools like AllScan or AllMon. Voice control removes that barrier:
connecting, disconnecting, or switching nodes needs only a spoken command
to Alexa, with no screen, keyboard, or CLI required.

Credit to **G5TOM** and **M7VDX** for the inspiration behind this project.

Hopefully this, or something like it, eventually makes its way into
official builds of ASL3 and HamVOIP, so voice commands can change or
disconnect nodes natively, without a separate Fauxmo/Alexa setup.

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


## TL;DR: quick setup

Check the Requirements section below first. Then, on your Pi/node:

```bash
# Get the code onto the Pi
sudo mkdir -p /opt/hamvox
sudo chown "$USER" /opt/hamvox
git clone <your-repo-url> /opt/hamvox
cd /opt/hamvox

# Set up the Python environment
sudo apt update
sudo apt install -y python3-venv python3-pip
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

# Install the wrapper scripts that Fauxmo calls via sudo
sudo cp scripts/allstar-cmd.sh /usr/local/bin/allstar-cmd.sh
sudo cp scripts/detect-node.sh /usr/local/bin/allstar-detect-node.sh
sudo chown root:root /usr/local/bin/allstar-cmd.sh /usr/local/bin/allstar-detect-node.sh
sudo chmod 755 /usr/local/bin/allstar-cmd.sh /usr/local/bin/allstar-detect-node.sh

# Create an unprivileged service user, and grant it passwordless
# sudo for those two wrapper scripts only
sudo useradd --system --no-create-home --shell /usr/sbin/nologin fauxmo
sudo visudo -f /etc/sudoers.d/allstar-cmd
# add: fauxmo ALL=(root) NOPASSWD: /usr/local/bin/allstar-cmd.sh
# add: fauxmo ALL=(root) NOPASSWD: /usr/local/bin/allstar-detect-node.sh
sudo chmod 440 /etc/sudoers.d/allstar-cmd

# Detect your local node number and write it into config/fauxmo.json
sudo scripts/configure-node.sh
sudo chown "$USER":"$USER" config/fauxmo.json

# Install and start the systemd service
sudo cp systemd/fauxmo.service /etc/systemd/system/fauxmo.service
sudo systemctl daemon-reload
sudo systemctl enable --now fauxmo
```

Then say "Alexa, discover devices." Full explanation of each step is in
Installation below.

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
  radio via `chan_simpleusb`/`chan_usbradio`). Fauxmo only issues link
  connect/disconnect commands over the network side of AllStar; it doesn't
  touch radio or audio configuration, so your node needs to already be
  transmitting and receiving correctly.
- **An Alexa device** (Echo, Echo Dot, etc.) on the **same LAN/subnet** as
  the Pi. Alexa discovers Fauxmo devices over local SSDP, which doesn't
  cross routed networks, VLANs, or the internet.
- **Python 3.9+** and **`sudo`/root access** on the Pi, to install Fauxmo,
  the wrapper scripts, and the systemd service.
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

`config/fauxmo.json` doesn't ship in the repo; `config/fauxmo.json.sample`
does. The first time you run `sudo scripts/configure-node.sh` (see
Installation below), it copies the sample to `config/fauxmo.json` if that
file doesn't exist yet, then fills in two things automatically: the
`path` to `plugins/allstar_plugin.py` (worked out from wherever you cloned
the repo, so it's correct even if you didn't use `/opt/hamvox`), and
`my_node` on every device, detected from Asterisk/`allstar.env`/`rpt.conf`.
Re-run it any time your local node number changes. You can also set
`my_node` to the literal string `"auto"` to have Fauxmo re-detect it on
every service start instead of baking in a static value; see
"Auto-detecting your node number" below for the trade-offs.

Edit `config/fauxmo.json` (not the `.sample`) to add, remove, or rename
devices/nodes. Each entry only needs `name`, a unique `port`, `my_node`,
and `target_node`. `config/fauxmo.json` is gitignored, since it holds your
own node numbers; `config/fauxmo.json.sample` is the tracked template.

## Repo layout

```
config/fauxmo.json.sample   Template config, copied to fauxmo.json on first run
config/fauxmo.json          Your device configuration (gitignored, edit this for your nodes)
plugins/allstar_plugin.py   Fauxmo plugin: on()/off() -> asterisk rpt commands
scripts/allstar-cmd.sh      Input-validated wrapper actually invoked via sudo
scripts/detect-node.sh      Detects local node number + system flavor
scripts/configure-node.sh   One-time setup: creates fauxmo.json, sets path, runs detect-node.sh
systemd/fauxmo.service      systemd unit to run Fauxmo as a background service
requirements.txt            Python dependencies
```

## How it stays safe to run with `sudo`

Fauxmo doesn't call `sudo asterisk -rx "..."` directly. It calls
`sudo /usr/local/bin/allstar-cmd.sh <my_node> <ilink> [<target_node>]`. The
wrapper script rejects anything that isn't a plain number before it reaches
Asterisk, and `sudoers` is scoped to that one script path. A broken config
value can't be used to run an arbitrary shell or Asterisk command as root.

## HamVOIP vs ASL3

This works unmodified on either. Both are Asterisk + `app_rpt`, and the
`ilink` function numbers this project calls (`6` = disconnect all, `3` =
connect transceive/permanent) are the same on both.

A few things to know when running on ASL3 specifically:

- **Asterisk runs as the `asterisk` user, not root.** This only matters if
  something talks to the Asterisk CLI without elevated privileges. Since
  `allstar-cmd.sh` is invoked via `sudo` (root) either way, no changes are
  needed; root can reach the Asterisk control socket on both platforms.
- **ASL3 also runs on amd64/x86, not just Raspberry Pi.** Nothing here is
  Pi-specific beyond the docs assuming a Pi. Install steps are identical on
  an x86 ASL3 box; just adjust the `/opt/hamvox` path if you prefer a
  different location.
- **Double-check `my_node` in `config/fauxmo.json`.** Make sure it matches
  the node number actually registered on your ASL3 install (portal
  registration works differently from HamVOIP, so it's easy to have a
  stale number after a migration).
- Everything else (wrapper script, sudoers entry, systemd unit, Fauxmo
  config) is identical between the two.

## Installation (Raspberry Pi running HamVOIP/AllStar)

Run these on the same Pi where Asterisk/`app_rpt` is running. `asterisk -rx`
only works against a local Asterisk instance.

### 1. Get the code onto the Pi

```bash
sudo mkdir -p /opt/hamvox
sudo chown "$USER" /opt/hamvox
git clone <your-repo-url> /opt/hamvox
cd /opt/hamvox
```

(If you're copying this from elsewhere instead of cloning, just get the
whole folder onto the Pi at that path, or adjust the paths in
`config/fauxmo.json` and `systemd/fauxmo.service` if you use a different one.)

### 2. Python environment

```bash
sudo apt update
sudo apt install -y python3-venv python3-pip
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate
```

### 3. Install the wrapper scripts

```bash
sudo cp scripts/allstar-cmd.sh /usr/local/bin/allstar-cmd.sh
sudo cp scripts/detect-node.sh /usr/local/bin/allstar-detect-node.sh
sudo chown root:root /usr/local/bin/allstar-cmd.sh /usr/local/bin/allstar-detect-node.sh
sudo chmod 755 /usr/local/bin/allstar-cmd.sh /usr/local/bin/allstar-detect-node.sh
```

### 4. Create a dedicated service user

Running Fauxmo as its own unprivileged user (rather than `pi` or `root`)
limits what a bug or compromise in Fauxmo could touch.

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin fauxmo
```

### 5. Grant that user passwordless sudo for the wrapper only

```bash
sudo visudo -f /etc/sudoers.d/allstar-cmd
```

Add these lines, save, and exit:

```
fauxmo ALL=(root) NOPASSWD: /usr/local/bin/allstar-cmd.sh
fauxmo ALL=(root) NOPASSWD: /usr/local/bin/allstar-detect-node.sh
```

The second line is only needed if you use `"my_node": "auto"` in
`config/fauxmo.json` (see step 6). The Fauxmo service itself never calls
the detect script otherwise, so skip that line if every device has a plain
numeric `my_node`.

Lock down the permissions on the sudoers snippet itself:

```bash
sudo chmod 440 /etc/sudoers.d/allstar-cmd
```

### 6. Detect and configure your node number

Instead of hand-editing `my_node` in `config/fauxmo.json`, let the repo
find it for you:

```bash
sudo scripts/configure-node.sh
sudo chown "$USER":"$USER" config/fauxmo.json
```

If `config/fauxmo.json` doesn't exist yet, this creates it from
`config/fauxmo.json.sample` first. It then sets the plugin `path` to
`plugins/allstar_plugin.py`'s actual location, runs `detect-node.sh`
(checking `allstar.env`, then `rpt nodes`, then `rpt.conf`, in that order),
prints the detected node number and whether it thinks this is HamVOIP or
ASL3, and writes that node number into every device in
`config/fauxmo.json`. Re-run it any time your node number changes.

### 7. Install and start the systemd service

```bash
sudo cp systemd/fauxmo.service /etc/systemd/system/fauxmo.service
sudo systemctl daemon-reload
sudo systemctl enable --now fauxmo
```

Check it came up cleanly:

```bash
sudo systemctl status fauxmo
journalctl -u fauxmo -f
```

### 8. Network / firewall notes

- Alexa devices discover Fauxmo devices over **SSDP (UDP 1900)**, then talk
  to each device's own TCP port (12340-12345 above), all on your LAN.
- Fauxmo and your Echo device(s) must be on the same subnet/VLAN. Alexa
  cannot discover Fauxmo devices across routed networks or over the
  internet.
  
If you run `ufw` (the default on Raspberry Pi OS), open the SSDP port and
the device port range. Replace `192.168.1.0/24` with your own LAN subnet:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 1900 proto udp
sudo ufw allow from 192.168.1.0/24 to any port 12340:12345 proto tcp
sudo ufw reload
```

If you run `firewalld` instead (more common on ASL3/x86 boxes):

```bash
sudo firewall-cmd --permanent --add-port=1900/udp
sudo firewall-cmd --permanent --add-port=12340-12345/tcp
sudo firewall-cmd --reload
```

Adding a new device in `config/fauxmo.json` with a port outside
12340-12345 means updating these rules to match.


### 9. Tell Alexa to discover the devices

Open the Alexa app: Devices > **+** > Add Device > **Other** >
"Discover devices", or just say:

> "Alexa, discover devices."

You should see the six names above show up as switches.

## Auto-detecting your node number

There are two ways to keep `my_node` correct. One is enough for most
people:

- **Recommended: bake it in once with `configure-node.sh`** (step 6
  above). Detection runs a single time during setup, the result is written
  as a plain number into `config/fauxmo.json`, and Fauxmo never has to
  shell out or need extra sudo access to figure out its own node number at
  runtime. Re-run the script if the node number ever changes.
- **Optional: `"my_node": "auto"` in the config.** The plugin calls
  `allstar-detect-node.sh` itself the first time it's needed after Fauxmo
  starts (cached after that, so it only runs once per service start). Use
  this if the node number genuinely changes between boots and you don't
  want to re-run the setup script. Requires the extra `sudoers` line from
  step 5, and adds a small amount of startup latency and one more thing
  that can fail (e.g. if Asterisk isn't up yet when Fauxmo starts).

Both use the same detection logic in `scripts/detect-node.sh`: it tries
`NODE1` from `/usr/local/etc/allstar.env` (common on HamVOIP), then falls
back to asking Asterisk directly (`rpt nodes`), then falls back to reading
the first node stanza out of `/etc/asterisk/rpt.conf`. System flavor
(HamVOIP vs ASL3) is detected too and printed for information; the
underlying `ilink` commands are identical on both, so flavor doesn't change
behavior, it's just handy for diagnostics.

## Verifying node status manually

To confirm connections independent of Alexa/Fauxmo, run the same kind of
status query you'd use directly on the Pi:

```bash
sudo /usr/sbin/asterisk -rx "rpt cmd 1998 status 11 xxx"
```

(Substitute your own node number for `1998`.)

## Troubleshooting

- **Alexa says "device is not responding"**: check `journalctl -u fauxmo -f`
  while you speak the command. Fauxmo logs each on/off call and any
  wrapper script errors.
- **"Invalid my_node" / "Invalid target_node" in the logs**: a value in
  `config/fauxmo.json` isn't purely numeric. Fix it there.
- **`sudo: a password is required`**: the sudoers line in step 5 wasn't
  applied to the `fauxmo` user, or the path doesn't exactly match
  `/usr/local/bin/allstar-cmd.sh` (or `/usr/local/bin/allstar-detect-node.sh`
  if you're using `"my_node": "auto"`).
- **`node auto-detection failed` in the logs**: only relevant if you're
  using `"my_node": "auto"`. Usually means the `sudoers` line for
  `allstar-detect-node.sh` is missing, or Asterisk wasn't fully up yet when
  Fauxmo started. Switch to a plain numeric `my_node` (via
  `configure-node.sh`) to remove this as a startup dependency entirely.
- **Devices don't show up on "discover devices"**: double check the Pi and
  Echo are on the same LAN/subnet, and that UDP 1900 isn't blocked.

## Customizing

- **Add a node**: add another object to the `DEVICES` array in
  `config/fauxmo.json` with a new `name`, a unique `port`, and the
  `target_node`. No code changes needed.
- **Change the ilink mode** (e.g. monitor-only instead of transceive): edit
  `ILINK_CONNECT_TRANSCEIVE_PERMANENT` in `plugins/allstar_plugin.py`
  (AllStar ilink function reference: `1`=disconnect one, `2`/`3`=connect
  transceive (temporary/permanent), `6`=disconnect all, `7`/`8`=monitor
  modes).

## License

MIT. See `LICENSE`.
