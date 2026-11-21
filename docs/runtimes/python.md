# python

system python, venvs, pipx for cli tools, uv for everything else.

## what is installed

`python3`, `python3-dev`, `python3-venv`, `python3-pip`, `pipx`, and `uv` in
`/usr/local/bin`.

trixie marks the system python as externally managed (pep 668). `pip install`
outside a venv fails on purpose, and `--break-system-packages` is how you break
the distro tooling. do not.

## daily use

```bash
uv venv
uv pip install -r requirements.txt
uv run pytest
```

or the old road:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -e .
```

cli tools:

```bash
pipx install ruff
pipx install httpie
pipx list
```

`pipx ensurepath` runs as `NEW_USER` during install. open a new shell, or source
`~/.profile`, before expecting the `~/.local/bin` entries to appear.

## why uv

it is a single static binary, resolves faster than pip, manages python versions
with `uv python install`, and does not care about the system interpreter. the
installer is the one `curl | sh` in this repo, pinned to `/usr/local/bin` and
skipped on reruns.

if a box should stay apt-only, `PYTHON_INSTALL_UV=0` and move on.

## versions

trixie ships python 3.13. if an app pins something older, use uv's managed
interpreters or a container. do not compile python from source on a vps unless
you enjoy a 20 minute `make` and a missing `libssl-dev` at the end of it.
