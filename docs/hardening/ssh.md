# ssh

goal: the only way in is a key, for one non-root user. real ssh defaults to
`1/tcp`. a separate [reject-only decoy](ssh-prank.md) owns `22/tcp`.

## what gets written

`/etc/ssh/sshd_config.d/00-postinstall.conf`, mode 0600. the `00-` prefix is not
cosmetic: sshd takes the first value it sees for most keywords, and the main
`sshd_config` includes `sshd_config.d/*.conf` at the top. cloud-init writes
`50-cloud-init.conf` and loves `PasswordAuthentication yes`. sorting first wins.

effective settings:

| setting | value | note |
| --- | --- | --- |
| `PermitRootLogin` | `no` | root exists, root just cannot log in over ssh |
| `PasswordAuthentication` | `no` | unless `SSH_ALLOW_PASSWORD=1` |
| `KbdInteractiveAuthentication` | `no` | the other password path |
| `AuthenticationMethods` | `publickey` | only added when passwords are off |
| `PermitEmptyPasswords` | `no` | |
| `MaxAuthTries` | `3` | |
| `LoginGraceTime` | `20` | |
| `X11Forwarding` | `no` | |
| `AllowTcpForwarding` | `yes` | controlled by `SSH_ALLOW_TCP_FORWARDING` |
| `AllowUsers` | `NEW_USER` | controlled by `SSH_ALLOW_USERS`; disabled accounts are filtered out |
| `DenyUsers` | `DISABLE_DEFAULT_USERS` | deny wins over allow when cloud-init fights back |
| `LogLevel` | `VERBOSE` | fingerprint logging, more for the journal |

`sshd -t` runs before any restart. if it fails the script stops with the old
config still active. that is the whole safety story: a config that does not
parse never reaches a restart.

## keys come first

`users` installs `SSH_PUBKEY` (inline, one key), `SSH_PUBKEY_FILE` (one key per
line, relative paths resolve against the repo), or leaves an existing
`/home/NEW_USER/.ssh/authorized_keys` alone. only when none of those exist does
it fall back to `/root/.ssh/authorized_keys`. an explicitly selected source that
is missing or malformed aborts the run instead of silently using the fallback.
it sets ownership and `0600`, and only then does `ssh` run. if no key exists
anywhere, `ssh` refuses to disable passwords unless you set
`SSH_ALLOW_PASSWORD=1`.

that refusal is the point. the script is allowed to be annoying. it is not
allowed to lock you out. the guard also checks the effective home from the
account database, key material, `.ssh` mode `0700`, owner, and `0600` on
`authorized_keys` before it writes the password-only-off config.

## the bootstrap account and the old one

`NEW_USER` needs a local password for `sudo`, not for SSH. SSH remains
public-key only: `SSH_ALLOW_PASSWORD=0`, `PasswordAuthentication no` and
`AuthenticationMethods publickey`. the local password is never accepted by
sshd.

the default is a password generated on the host at deploy time. the module
creates a 64-character hex password with `openssl rand -hex 32` and stores it at
`/root/postinstall-<user>.password`, mode `0600`. it is never printed and is
removed from the exported environment before apt or curl sees it. read it from
the open root session or the provider console, then rotate with
`passwd NEW_USER` if you want a different one. reruns do not rotate a password
that is already set; remove or update the generated file after rotating.

`SUDO_NOPASSWD=0` keeps the sudo prompt. `SUDO_NOPASSWD=1` is optional and only
skips that prompt; neither setting adds a password path to SSH.

an explicit `NEW_USER_PASSWORD` or `NEW_USER_PASSWORD_FILE` is possible but
opt-in. leave both empty for the generated flow. a chosen file must be mode
`0400` or `0600`; relative paths resolve against the repo and the file is
gitignored.

`DISABLE_DEFAULT_USERS` defaults to `debian`. the module refuses to touch the
old account until `NEW_USER` has a usable key, or until you explicitly set
`SSH_ALLOW_PASSWORD=1` (not recommended) to make a password a way in. then, per
account:

- remove sudo and docker membership
- shell to `/usr/sbin/nologin`
- lock the password
- expire the account (`chage -E 1`)
- terminate sessions and remaining processes
- scrub sudoers lines that name the account, including cloud-init's
  `90-cloud-init-users`
- add the account to sshd `DenyUsers`

`NEW_USER` is rejected if it appears in the disable list. the audit checks the
shell, lock, expiry, groups, sudoers grants and effective `AllowUsers` /
`DenyUsers` values.

## socket activation

debian 13 listens through `ssh.socket`, not `ssh.service`. the port lives here:

```ini
# /etc/systemd/system/ssh.socket.d/10-postinstall-port.conf
[Socket]
ListenStream=
ListenStream=1
```

the blank `ListenStream` resets the unit's own value before setting yours.
after that: `systemctl daemon-reload && systemctl restart ssh.socket`.

`systemctl status ssh.socket` shows the current listen address. `ss -ltnp |
grep sshd` shows the truth.

## changing the port later

1. edit `SSH_PORT` in the config
2. `sudo bash debian13-postinstall.sh --only firewall,ssh,ssh_prank,fail2ban`
3. the firewall opens the new port before sshd moves, fail2ban follows
4. open a new session on the new port before closing the old one

the audit checks that something actually listens on `SSH_PORT`, which catches
the classic "changed the config, did not restart anything" case.

## recovery

existing sessions are not killed by a socket or sshd restart. if you have one,
keep it open while you work.

from a session:

```bash
sudo sshd -t
sudo systemctl restart ssh.socket   # socket activation
sudo systemctl restart ssh          # service mode
```

without a session: provider console or rescue mode, edit
`/etc/ssh/sshd_config.d/00-postinstall.conf`, run `sshd -t`, restart. the
firewall is a separate failure: if the port is not in the nftables ruleset no
amount of sshd fixing helps.

## why port 1

port `1/tcp` is the chosen default to reduce noise aimed at common ssh ports.
it does not stop a full port scan. authentication stays key-only and fail2ban
protects real ssh on the configured port.

existing config files override the new default. change `SSH_PORT=22` to
`SSH_PORT=1` to adopt it, and allow tcp/1 at the provider firewall.
keep the current session open and prove a separate login works:

```bash
ssh -p 1 ops@example.com
```

`SSH_PORT=22` is rejected before changes when the decoy is selected or running.
