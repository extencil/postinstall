# postinstall

scripts that turn a fresh vps into a box i don't have to think about again.

![debian 13](https://img.shields.io/badge/debian-13%20trixie-A81D33?style=flat-square&logo=debian&logoColor=white)
![bash](https://img.shields.io/badge/bash-5.x-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![cloudflare](https://img.shields.io/badge/cloudflare-tunnel%20%2B%20mesh-F38020?style=flat-square&logo=cloudflare&logoColor=white)
![license](https://img.shields.io/badge/license-Unlicense-lightgrey?style=flat-square)

every provider hands you a root shell, a password in an email and a vague feeling
that you forgot something. this repo is the thing i kept forgetting.

one entrypoint per distro. debian 13 is the one that matters, the rest is a
directory layout waiting to happen.

## the deal

- `debian13-postinstall.sh` applies my defaults to a fresh debian 13 box.
- `audit/debian13-audit.sh` reads the box back and tells me what drifted.
- `config/postinstall.env` holds the opinions (user, port, tokens, modules).
- `docs/` holds the "why", per topic, so future me stops guessing.

it is idempotent. run it once after the provider mail, run it again next month
after adding a module. it skips what already matches, backs up what it rewrites.

> [!WARNING]
> this disables root ssh and password auth. if there is no key for the new user
> you will lose the box. the script refuses to continue when it detects that,
> but read [docs/hardening/ssh.md](docs/hardening/ssh.md) before you find out
> the hard way.

## quick start

```bash
git clone https://github.com/extencil/postinstall
cd postinstall

install -m 0600 config/postinstall.env.example config/postinstall.env
$EDITOR config/postinstall.env       # user, port, timezone, modules

sudo bash debian13-postinstall.sh --dry-run
sudo bash debian13-postinstall.sh
```

end to end on a fresh box, no menu, no prompts. the only thing that can ask you
anything is apt.

then prove you can log in as the new user on the new port before you close the
root shell. use the provider console if you enjoy not being locked out.

the generated password is never printed. it lands in
`/root/postinstall-<user>.password` (mode `0600`). with `SUDO_NOPASSWD=0`, read
it as root from the provider console before you rely on password-based sudo.

## what runs, in order

order is not decoration. the firewall opens `SSH_PORT` before sshd moves to it,
and fail2ban starts after the ruleset exists. real ssh defaults to `1/tcp`;
use `ssh -p 1 ops@example.com` for a fresh deployment. the decoy takes `22/tcp`
after real ssh moves. existing configs keep their explicit `SSH_PORT`; change
`22` before upgrading with the decoy enabled.

```mermaid
flowchart LR
    preflight --> users --> firewall --> ssh --> ssh_prank --> fail2ban --> sysctl
    sysctl --> updates --> tools --> shell --> docker --> python
    python --> cloudflare --> dotfiles --> audit
```

`node`, `go`, `warp` and `dotfiles` are off by default. cloudflared too, until
you put a token in the config.

| module | what it actually does |
| --- | --- |
| `preflight` | debian check, apt index, timezone, timesyncd, hostname |
| `users` | creates `NEW_USER`, generated password, sudo, ssh key, locks root, disables `debian` |
| `firewall` | nftables, input drop, only ssh + your extra ports |
| `ssh` | key only, no root, real ssh on tcp/1, socket aware |
| `ssh_prank` | reject-only decoy on tcp/22, bounded connections, separate service |
| `fail2ban` | sshd jail reading the journal, bans in nftables |
| `sysctl` | kernel and network knobs, the safe ones |
| `updates` | unattended security upgrades, no surprise reboots |
| `tools` | git, tmux, ripgrep, fd, bat, btop, mtr, the usual bag |
| `shell` | zsh as login shell, dotfiles do the rc files |
| `docker` | upstream repo, log rotation, no-new-privileges |
| `python` | venv, pipx, uv |
| `node` | nodesource apt repo, pinned major (optional) |
| `go` | distro golang (optional) |
| `cloudflared` | named tunnel, outbound only (optional) |
| `warp` | cloudflare mesh connector (optional) |
| `dotfiles` | clones the repo that makes the box mine (optional) |
| `verify` | runs the audit at the end, never fails the run |

flags:

```bash
sudo bash debian13-postinstall.sh --dry-run
sudo bash debian13-postinstall.sh --only firewall,ssh,ssh_prank,fail2ban
sudo bash debian13-postinstall.sh --skip docker,node,go
sudo bash debian13-postinstall.sh --user ops --port 2222 --timezone Europe/Amsterdam
sudo bash debian13-postinstall.sh --list
sudo bash debian13-postinstall.sh --audit
```

## config

`config/postinstall.env.example` is the whole surface. it is a shell file, so
anything you can write in bash works, including `$(cat token)`. two things to
know:

- it holds tunnel tokens and, if you set one, a bootstrap password. keep it
  out of git, keep it `0600`, and prefer token files over inlining the token.
- precedence is flags > config file > environment > defaults.

the parts people touch:

```bash
NEW_USER=ops
NEW_USER_PASSWORD=""                 # empty = generate 64 hex chars on first run
NEW_USER_PASSWORD_FILE=""            # empty = /root/postinstall-<user>.password
DISABLE_DEFAULT_USERS=debian         # lock, expire, nologin, deny ssh
SSH_PORT=1
TIMEZONE=UTC
SSH_PUBKEY_FILE=/root/.ssh/authorized_keys

CLOUDFLARED_TOKEN_FILE=/root/.secrets/cf-tunnel.token
CLOUDFLARE_WARP_TOKEN_FILE=/root/.secrets/cf-warp.token

ENABLE_DOCKER=1
ENABLE_CLOUDFLARED=1
ENABLE_WARP=0
```

<details>
<summary>every knob and its default</summary>

| key | default | what |
| --- | --- | --- |
| `NEW_USER` | `ops` | the human account |
| `NEW_USER_PASSWORD` | empty | explicit bootstrap password; empty generates 64 hex chars |
| `NEW_USER_PASSWORD_FILE` | empty | generated password path, default `/root/postinstall-<user>.password` |
| `DISABLE_DEFAULT_USERS` | `debian` | provider accounts to lock, expire, nologin and deny over ssh |
| `SSH_PORT` | `1` | real ssh port, firewall follows; decoy uses `22` |
| `SSH_PRANK_BANNER_FILE` | empty | optional public UTF-8 banner for the decoy |
| `HOSTNAME_SET` | empty | leave the provider hostname alone |
| `TIMEZONE` | `UTC` | iana name |
| `SSH_PUBKEY_FILE` | empty | key file, relative paths resolve against the repo; falls back to `/root/.ssh/authorized_keys` |
| `SSH_PUBKEY` | empty | inline public key, wins over the file |
| `SSH_ALLOW_USERS` | empty | empty means only `NEW_USER`; disabled accounts are filtered out |
| `SSH_ALLOW_PASSWORD` | `0` | set `1` only if you enjoy passwords |
| `SSH_ALLOW_TCP_FORWARDING` | `1` | keep `-L`/`-R` working |
| `EXTRA_TCP_PORTS` | empty | inbound tcp, space or comma separated |
| `EXTRA_UDP_PORTS` | empty | inbound udp |
| `SUDO_NOPASSWD` | `0` | passwordless sudo for `NEW_USER` |
| `DOCKER_ADD_USER_TO_GROUP` | `1` | root-equivalent, read the docker doc |
| `PYTHON_INSTALL_UV` | `1` | uv into `/usr/local/bin` |
| `NODE_MAJOR` | `24` | nodesource major |
| `CLOUDFLARED_TOKEN_FILE` | empty | tunnel token, `0600` |
| `CLOUDFLARE_WARP_TOKEN_FILE` | empty | mesh connector token, `0600` |
| `WARP_CODENAME` | `bookworm` | until upstream ships trixie |
| `DOTFILES_REPO` | empty | git url, cloned as `NEW_USER` |
| `DOTFILES_DIR` | empty | defaults to `~/.dotfiles` |
| `DOTFILES_INSTALL_CMD` | empty | run inside the clone, as the user |
| `DOTFILES_UPDATE` | `1` | `git pull --ff-only` on reruns |
| `ENABLE_*` | per module | `0` skips it, `--only`/`--skip` override |

</details>

## audit

read only, prints `ok` / `warn` / `FAIL` per check, exit 1 if anything failed.
that makes it usable from cron or a pre-change gate.

```bash
sudo bash audit/debian13-audit.sh
sudo bash audit/debian13-audit.sh --quiet
sudo bash audit/debian13-audit.sh --config config/postinstall.env
```

```text
== ssh
  ok   sshd permitrootlogin no
  ok   sshd passwordauthentication no
  ok   drop-in /etc/ssh/sshd_config.d/00-postinstall.conf present
  ok   something listens on tcp/1
== firewall
  ok   table inet filter present
  ok   input policy drop
  ok   tcp/1 allowed in
== score
  31 ok  2 warn  0 fail  3 skip
```

it checks ssh effective config (not just the file), the live nftables ruleset,
jail status, every sysctl it deployed, timers, packages, docker daemon keys,
cloudflare units, world-facing listeners and the pending-reboot flag.

details and exit codes: [docs/audit.md](docs/audit.md).

## repo layout

```text
.
├── debian13-postinstall.sh       # entrypoint, flags, module runner
├── AGENTS.md                     # canonical llm/harness contract
├── config/
│   └── postinstall.env.example   # copy to postinstall.env, gitignored
├── lib/
│   ├── common.sh                 # logging, run(), write_file(), backups
│   └── modules/                  # one file per topic, numbered by order
├── audit/
│   └── debian13-audit.sh         # read-only report card
└── docs/
    ├── debian-13.md              # trixie specific gotchas
    ├── hardening/                # ssh, firewall, fail2ban, sysctl, updates
    ├── network/cloudflare.md     # tunnel and mesh, the outbound way
    ├── runtimes/                 # docker, python, node, go
    ├── shell/tooling.md
    ├── secrets/dotfiles.md
    └── checklists/new-vps.md     # the boring paper checklist
```

`AGENTS.md` is the canonical instruction file for llms and harnesses.
`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`,
`.cursor/rules/postinstall.mdc` and `llms.txt` are thin pointers so every tool
lands in the same place instead of inventing its own rules.

## docs

| doc | read it when |
| --- | --- |
| [debian 13 notes](docs/debian-13.md) | the box is trixie and something behaves oddly |
| [ssh](docs/hardening/ssh.md) | port changed, socket activation, lockout recovery |
| [ssh prank](docs/hardening/ssh-prank.md) | port 22 decoy, limits, deployment and recovery |
| [firewall](docs/hardening/firewall.md) | adding a port, docker + nftables, debugging drops |
| [fail2ban](docs/hardening/fail2ban.md) | checking or lifting a ban |
| [sysctl](docs/hardening/sysctl.md) | wondering what a knob does and why it is not here |
| [updates](docs/hardening/updates.md) | controlling the 6am upgrade window |
| [cloudflare](docs/network/cloudflare.md) | tunnel vs mesh, tokens, zero inbound |
| [docker](docs/runtimes/docker.md) | daemon.json choices and the group warning |
| [python](docs/runtimes/python.md) | uv, pipx, venvs |
| [node and go](docs/runtimes/node-go.md) | version pins, why optional |
| [tooling](docs/shell/tooling.md) | package list and the bat/fd renames |
| [dotfiles and secrets](docs/secrets/dotfiles.md) | age, sops, gpg, clone order |
| [audit](docs/audit.md) | wiring it into cron |
| [new vps checklist](docs/checklists/new-vps.md) | provider day |
| [agent notes](AGENTS.md) | working on the repo with an llm |

## what this is not

- not a cis benchmark runner. no compliance checkbox, no scoring dashboard.
- not a monitoring stack. uptime checks live somewhere else.
- not protection from root. if someone is root, the box is theirs.
- not a backup system. a hardened box that loses its data is still a lost box.
- not distro agnostic. trixie-only, on purpose. `apt` and systemd everywhere.

things left alone deliberately: `ip_forward` (docker), ipv6 `accept_ra` (some
providers hand v6 out over RA and disabling it drops the address), docker's
rootless userns settings, and anything that needs a reboot to prove itself.

## contributing

pending work and verification checks live in [TODO.md](TODO.md).

issues and prs are welcome. keep it boring: apt packages over curl installers,
idempotent over clever, one module per topic, and update the audit when you add
a module that changes state. use conventional commits with an imperative
subject and explain migration steps and validation when relevant.

the shellcheck line:

```bash
shellcheck -x debian13-postinstall.sh lib/common.sh lib/modules/*.sh audit/*.sh
```

## community

join [haltman](https://haltman.io/join/) or go straight to the
[telegram group](https://t.me/haltman_group).

## license

unlicense. it is a shell script, not a startup. see [LICENSE](LICENSE).
