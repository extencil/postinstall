# ssh

goal: the only way in is a key, for one non-root user, on a port i know.

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
| `AllowUsers` | `NEW_USER` | controlled by `SSH_ALLOW_USERS` |
| `LogLevel` | `VERBOSE` | fingerprint logging, more for the journal |

`sshd -t` runs before any restart. if it fails the script stops with the old
config still active. that is the whole safety story: a config that does not
parse never reaches a restart.

## keys come first

`users` copies `SSH_PUBKEY_FILE` (default `/root/.ssh/authorized_keys`) into
`/home/NEW_USER/.ssh/authorized_keys`, sets ownership and `0600`, and only then
does `ssh` run. if no key exists anywhere, `ssh` refuses to disable passwords
unless you set `SSH_ALLOW_PASSWORD=1`.

that refusal is the point. the script is allowed to be annoying. it is not
allowed to lock you out.

## socket activation

debian 13 listens through `ssh.socket`, not `ssh.service`. the port lives here:

```ini
# /etc/systemd/system/ssh.socket.d/10-postinstall-port.conf
[Socket]
ListenStream=
ListenStream=2222
```

the blank `ListenStream` resets the unit's own value before setting yours.
after that: `systemctl daemon-reload && systemctl restart ssh.socket`.

`systemctl status ssh.socket` shows the current listen address. `ss -ltnp |
grep sshd` shows the truth.

## changing the port later

1. edit `SSH_PORT` in the config
2. `sudo bash debian13-postinstall.sh --only firewall,ssh,fail2ban`
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

## why not port 22 with fail2ban

you can. the script does not care. a non-default port removes noise, not
determination. fail2ban and keys do the actual work. changing the port is a
preference, not a security boundary.
