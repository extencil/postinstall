# fail2ban

one jail, sshd, reading the journal. bans go into nftables. default is one hour
after five failures in ten minutes.

## config

`/etc/fail2ban/jail.d/postinstall.local`:

```ini
[DEFAULT]
backend = systemd
banaction = nftables-multiport
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = 1
mode = aggressive
```

- `backend = systemd` reads `journalctl` instead of `/var/log/auth.log`.
  trixie does not install rsyslog by default, so file backends find nothing.
- `nftables-multiport` keeps everything in nftables. if the installed fail2ban
  predates that action, the module falls back to `iptables-multiport`, which on
  debian is nft underneath anyway.
- `mode = aggressive` enables the extra sshd regexes (invalid user, preauth
  disconnect spam). more matches, still low false positives with keys only.
- `ignoreip` only localhost by default. add your admin addresses if you connect
  through a fixed egress.

the jail follows `SSH_PORT` and watches real sshd. the decoy runs as a
separate service, and its traffic does not feed this jail.

## commands

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip 203.0.113.7
sudo fail2ban-client set sshd banip 203.0.113.7
sudo fail2ban-client -t                 # config test
sudo journalctl -u fail2ban --since -30min
```

`Status for the jail: sshd` with a ban count means it works. `Failed to access
socket` usually means the service is not running, not that the jail is broken.

## why not more jails

web app jails (`nginx-http-auth`, `nginx-botsearch`, `wordpress`) belong next to
the app, not in a base image script. a box without nginx should not carry an
nginx jail that logs errors every minute.

if you add one, drop it in `jail.d/` as a separate file, then
`fail2ban-client -t && systemctl restart fail2ban`.

## interaction with the ruleset

bans are kernel state in fail2ban's own table. `nftables.service` restart flushes
all tables, so the module restarts fail2ban right after. if you reload the
firewall by hand, do the same or the current bans are gone until they expire.

`fail2ban-client status sshd` shows `Currently banned` and `Total banned`.
the audit prints those numbers.
