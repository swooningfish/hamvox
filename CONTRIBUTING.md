# Contributing

Thanks for your interest in HamVox.

* Feel free to open issues for bugs, feature requests, questions, or ideas.
* For a small fix, open a PR directly.
* For anything larger (a new feature, a different config format, a new
  radio/network backend), open an issue first so it can be discussed.
* Please update `README.md` when you change behavior (new config options,
  new install steps, new devices, etc).
* Keep commits focused, with clear commit messages.

## Code of conduct

Be respectful and constructive. This is a small hobby project run by radio
amateurs in their spare time.

## Development

* This is a small project: a couple of shell scripts plus a Home Assistant
  `command_line` switch config. There's no automated test suite yet, so
  test changes against a real AllStarLink or HamVOIP node before opening a
  PR.
* `config/homeassistant/hamvox.yaml.sample` defines one Home Assistant
  switch per node (`command_on`/`command_off` map to Asterisk `rpt`
  commands via the wrapper script).
* `scripts/hamvox-asterisk-cmd.sh` and `scripts/detect-node.sh` are the shell
  wrappers that Home Assistant calls via `sudo`. Keep changes to these
  minimal and well tested, since they run with elevated privileges. See
  "How it stays safe to run with sudo" in `README.md` before touching
  either script.
* See `README.md` for local setup and installation steps.

## Adding support for something new

If you add support for a different radio control system or network
backend, follow the same pattern as `config/homeassistant/hamvox.yaml.sample`:
one switch per target, each calling a small input-validated wrapper script
via `sudo`, never the underlying CLI directly.
