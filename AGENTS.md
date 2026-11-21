# AGENTS.md

operating manual for any llm or harness working in this repo. read it before
editing. it is shorter than the docs and more binding than the readme.

## what this repo is

shell scripts that turn a fresh debian 13 vps into a known-good box.

- `debian13-postinstall.sh` deploys. one entrypoint per distro, trixie today.
- `audit/debian13-audit.sh` verifies. read only, never fixes.
- `config/postinstall.env` holds the opinions. gitignored, example committed.
- `lib/modules/*.sh` one file per topic, sourced by the entrypoint in order.

bash 5, systemd, apt. the ssh decoy uses system python and python3-paramiko
from apt on the target host. no build step, no ci, no pip environment.

## the contract

these are not preferences. breaking one is a bug.

1. **idempotent.** every module checks state and skips when it already matches.
   rerunning the script must be a no-op, not a second install.
2. **non-interactive.** no prompts, no `read`, no editor. apt gets `-y`.
   `--yes` exists for muscle memory only.
3. **back up before overwrite.** only `write_file` writes config files. it
   compares content, copies the old file to `/var/backups/postinstall/<ts>/`,
   then installs. do not `cp` or `cat >` managed files.
4. **dry-run means dry.** every mutating command goes through `run()`. a raw
   `systemctl restart`, `apt-get`, `usermod` or redirect in a module is wrong.
   read-only commands (`grep`, `ss`, `id`, `systemctl is-active`) go direct.
5. **root required, never on a dev box.** the full run changes sshd, the
   firewall, users and packages. only run it in a disposable debian 13 vm or
   container. `--dry-run` still needs root because `require_root` runs first.
6. **audit stays in sync.** a module that changes system state gets a matching
   read-only check in the audit, in the same change.
7. **no new dependencies.** apt packages, coreutils, systemd. the only
   `curl | sh` is the uv installer. do not add npm/pip/rust bootstraps.
8. **no secrets in the repo.** tokens live in 0600 files referenced by config.
   never print a token, never put one in a commit, log or example.

## map

```text
debian13-postinstall.sh     flags, config load, module runner, summary
lib/common.sh               log_*, run, run_as_user, install_pkgs, write_file,
                            ensure_dir, backup_file, service_*, enable_now
lib/modules/NN-name.sh      module_<id>() functions, sourced, not executable
audit/debian13-audit.sh     standalone, no lib dependency, ok/warn/FAIL
config/postinstall.env.example   the full config surface, commented
docs/                       reasoning per topic, linked from README
```

modules and their places:

| id | file | flag | doc |
| --- | --- | --- | --- |
| preflight | `00-preflight.sh` | always on, `--skip` works | `docs/debian-13.md` |
| users | `10-users.sh` | `ENABLE_USERS` | `docs/hardening/ssh.md` |
| firewall | `20-firewall.sh` | `ENABLE_FIREWALL` | `docs/hardening/firewall.md` |
| ssh | `30-ssh.sh` | `ENABLE_SSH` | `docs/hardening/ssh.md` |
| ssh_prank | `35-ssh-prank.sh` | `ENABLE_SSH_PRANK` | `docs/hardening/ssh-prank.md` |
| fail2ban | `40-fail2ban.sh` | `ENABLE_FAIL2BAN` | `docs/hardening/fail2ban.md` |
| sysctl | `50-sysctl.sh` | `ENABLE_SYSCTL` | `docs/hardening/sysctl.md` |
| updates | `60-updates.sh` | `ENABLE_UPDATES` | `docs/hardening/updates.md` |
| tools | `70-tools.sh` | `ENABLE_TOOLS` | `docs/shell/tooling.md` |
| shell | `75-shell.sh` | `ENABLE_SHELL` | `docs/shell/tooling.md` |
| docker | `80-docker.sh` | `ENABLE_DOCKER` | `docs/runtimes/docker.md` |
| python | `81-python.sh` | `ENABLE_PYTHON` | `docs/runtimes/python.md` |
| node | `82-node.sh` | `ENABLE_NODE` | `docs/runtimes/node-go.md` |
| go | `83-go.sh` | `ENABLE_GO` | `docs/runtimes/node-go.md` |
| cloudflared | `90-cloudflared.sh` | `ENABLE_CLOUDFLARED` | `docs/network/cloudflare.md` |
| warp | `91-warp.sh` | `ENABLE_WARP` | `docs/network/cloudflare.md` |
| dotfiles | `95-dotfiles.sh` | `ENABLE_DOTFILES` | `docs/secrets/dotfiles.md` |
| verify | `99-verify.sh` | `ENABLE_VERIFY` | `docs/audit.md` |

run order is the array at the top of the entrypoint, not the file names,
although they match on purpose: users exist before ssh hardens, the firewall
opens the port before sshd moves, the decoy starts after real ssh leaves
port 22, and fail2ban starts after the ruleset.

## how a run works

1. defaults are set with `: "${VAR:=value}"`
2. the config file is sourced with `set -a` (config beats environment)
3. flags are parsed (flags beat config)
4. `--list`, `--version`, `--help` exit before the root check
5. `require_root`, log file under `/var/log/postinstall`, tee
6. every enabled module is sourced and its `module_<id>` called
7. `verify` runs the audit; failures there warn, they do not fail the run

precedence: **flags > config file > environment > defaults.** do not flip it.

## module contract

- file `lib/modules/NN-name.sh`, defines one function `module_name`.
- add a `case` arm in the runner at the bottom of `debian13-postinstall.sh`.
  forgetting this is the classic silent no-op.
- add the `ENABLE_*` default in the entrypoint defaults block and in
  `config/postinstall.env.example`. a missing default is an unbound variable
  under `set -u`.
- start with `log_step "topic"`, then check state, then act.
- use `install_pkgs pkg...` instead of raw apt. it skips installed packages.
- use `write_file PATH MODE <<EOF` for managed files. unquoted heredoc when
  the content needs variables, quoted when it does not.
- check `LAST_WRITE_CHANGED` to decide about restarts.
- log with `log_ok`, `log_skip`, `log_warn`, `log_info`. no bare `echo`.
- `die` for states that would break access. warning is for drift, die is for
  lockout.
- do not `exit 0` inside a module, and do not source another module.

helpers you should not reinvent: `run`, `run_as_user`, `install_pkgs`,
`apt_update`, `refresh_apt`, `ensure_dir`, `backup_file`, `write_file`,
`service_active`, `service_enabled`, `enable_now`, `restart_if_changed`,
`debian_codename`, `debian_version_id`.

## adding a module

touch all of these or the change is incomplete:

1. `lib/modules/NN-name.sh` with `module_name`
2. `debian13-postinstall.sh`: default, `MODULES`, `case` arm
3. `config/postinstall.env.example`: flag and options, commented
4. `README.md`: module table row
5. `docs/<topic>.md`: what, why, failure mode, recovery command
6. `docs/README.md` and the README docs table if it is a new doc
7. `audit/debian13-audit.sh`: a check for the state it creates
8. `CHANGELOG.md`: one line under the current version

if any of 1-8 is missing, say so instead of calling it done.

## adding an audit check

- read only. no restart, no `nft add`, no install, no writes.
- one fact per line: `ok`, `warn`, `bad`, `skip`, plus `detail` for context.
- `bad` for "this breaks access or defeats a stated goal". `warn` for drift and
  root-equivalent choices. `skip` when the feature is not installed.
- exit code contract: 0 no failures, 1 at least one failure, 2 bad usage.
  warnings never change the code.
- check the kernel or effective config, not only the file. `sshd -T`, `nft list
  chain`, `sysctl -n`, `fail2ban-client status`.
- the audit must keep working without the config file and without root, just
  with skips and warnings.

## testing

the shell installer has no general test suite. these are the gates:

```bash
# syntax, every file
for f in debian13-postinstall.sh audit/*.sh lib/common.sh lib/modules/*.sh; do
  bash -n "$f" || exit 1
done

# lint (install shellcheck if missing)
shellcheck -x debian13-postinstall.sh lib/common.sh lib/modules/*.sh audit/*.sh

# behavior that needs no root and no state
bash debian13-postinstall.sh --list
bash debian13-postinstall.sh --help
bash debian13-postinstall.sh --version
bash audit/debian13-audit.sh --help
bash audit/debian13-audit.sh --no-color    # read only, full picture needs root
```

the decoy has isolated protocol and module checks in `tests/test_ssh_prank.py`.
run `python3 -B -m unittest discover -s tests -v` in a disposable debian 13
container with `python3-paramiko` available. these checks use temporary keys,
loopback sockets and mocked deploy commands; they do not run the entrypoint.
target dependencies belong in target-host modules, not the developer's WSL.

a full `--dry-run` needs root and a debian 13 host. do it in a disposable vm,
read the output, then throw the vm away. never "just run it" on a machine you
care about to see what happens.

## style

- artifacts are in english, lowercase headings, simple sentences. the readme
  has a dry voice and the odd joke. match it, do not add marketing.
- no ai filler: no "comprehensive", "seamless", "robust", no summary paragraph
  that repeats the diff, no emoji outside the readme badges.
- bash: quote variables, `local` inside functions, 2 space indent, `[[ ]]`,
  `$( )` not backticks, long options in docs.
- comments explain the trap, not the syntax. "cloud-init re-enables password
  auth" is useful. "install packages" is not.
- keep existing comments unless the behavior changed.

## git workflow

- complete relevant changes with commits and a push to the tracked remote.
  this is standing authorization; do not leave finished work local-only.
- use Conventional Commits: `type(scope): imperative summary`. add `!` and a
  `BREAKING CHANGE:` footer when defaults or behavior require migration.
- keep commits focused. explain the reason, resulting behavior, migration
  steps and validation in the body when relevant. write messages in English.
- update the todo, changelog, docs and audit alongside the implementation.
  separate local checks from proof on a deployed target.
- review the staged diff for secrets, real addresses and unrelated files.
  never publish unredacted screenshots or a real config file.
- check remote state before pushing. do not force-push or rewrite published
  history. verify that the remote branch points to the pushed commit.
- report commit links, checks and material limitations after publication.

## security rules

- never weaken the lockout guard in `30-ssh.sh`. no key plus no password must
  keep aborting. `SSH_ALLOW_PASSWORD=1` is the explicit opt-out.
- never add a default `PasswordAuthentication yes`, `PermitRootLogin yes`, or
  an open input policy.
- never commit real tokens, keys, hostnames or ip addresses, even in docs.
  examples use `203.0.113.7`, `example.com`, `ops`.
- do not run destructive commands to "verify" anything. no `rm -rf`, no
  `ufw disable`, no `systemctl stop ssh` as a test.
- do not paste secrets from config or unit files into chat, logs or a commit.

## known gotchas

- debian 13 uses `ssh.socket`. the port lives in a socket drop-in, not only in
  `sshd_config`. restart the socket, not just ssh.
- ssh uses first-value-wins across `sshd_config.d/*.conf`. our `00-` prefix is
  deliberate, cloud-init writes `50-` and re-enables password auth.
- `flush ruleset` kills docker's and fail2ban's tables. restart both after the
  firewall changes, which `20-firewall.sh` does.
- docker published ports bypass the input chain through nat/forward. the host
  firewall is not a substitute for binding to localhost.
- `ip_forward` and ipv6 `accept_ra` are intentionally absent from sysctl.
  docker and some providers need them.
- fail2ban on trixie needs `backend = systemd`; there is no `auth.log`.
- `--only` bypasses `ENABLE_*`. `preflight` still runs unless explicitly
  skipped, because every module assumes its checks and apt index.
- `pipx ensurepath` writes for the user, not root. run it via `run_as_user`.

## when in doubt

read the doc for the topic first, then the module, then the audit. if the three
disagree, the module is the source of truth for values and the audit is the
source of truth for what "done" means. fix the doc and the audit, do not
special-case the script.

ask before: changing a default that affects access (port, user, auth), deleting
a module, changing config precedence, adding a dependency, or running the
deploy script anywhere.
