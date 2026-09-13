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

* This is a small Python project built on
  [Fauxmo](https://github.com/n8henrie/fauxmo). There's no automated test
  suite yet, so test changes against a real AllStarLink or HamVOIP node
  before opening a PR.
* `plugins/allstar_plugin.py` is the Fauxmo plugin (`on()`/`off()` map to
  Asterisk `rpt` commands).
* `scripts/allstar-cmd.sh` and `scripts/detect-node.sh` are the shell
  wrappers that Fauxmo calls via `sudo`. Keep changes to these minimal and
  well tested, since they run with elevated privileges. See "How it stays
  safe to run with sudo" in `README.md` before touching either script.
* See `README.md` for local setup and installation steps.

## Adding support for something new

The plugin interface is `AllStarPlugin` in `plugins/allstar_plugin.py`,
which subclasses Fauxmo's `FauxmoPlugin`. If you add support for a
different radio control system or network backend, follow the same
`on()` / `off()` / `get_state()` pattern used there.
