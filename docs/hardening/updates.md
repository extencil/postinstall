# updates

security patches land without me reading a mail at 3am. reboots still need a
human.

## what is on

- `unattended-upgrades`, `apt-listchanges`, `needrestart`
- `/etc/apt/apt.conf.d/20auto-upgrades` turns the periodic job on
- `/etc/apt/apt.conf.d/52postinstall-unattended-upgrades` restricts origins to
  debian and debian-security, keeps auto-reboot off
- `apt-daily-upgrade.timer` does the actual running

the `52-` prefix sorts after the stock `50unattended-upgrades`, so these values
win while the package's own defaults stay in place. overwriting the stock file
is how people lose `AutoFixInterruptedDpkg` on a bad day.

## checking

```bash
systemctl list-timers apt-daily-upgrade.timer
systemctl status unattended-upgrades
sudo unattended-upgrade --dry-run --debug
grep -r . /etc/apt/apt.conf.d/ | grep -i unattended
```

the dry run prints the packages it would upgrade. it changes nothing.

## reboot policy

automatic reboot is off on purpose. a vps that reboots under you at 6am is a
story with a bad ending. when `/var/run/reboot-required` exists:

```bash
cat /var/run/reboot-required
cat /var/run/reboot-required.pkgs
```

schedule it. `needrestart` lists services that need a restart before a full
reboot is required, and `needrestart -r l` gives the interactive list.

## upgrade window

the timers fire on a randomized delay. if the box has a busy hour, pin the
window:

```bash
sudo systemctl edit apt-daily-upgrade.timer
```

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 04:30
RandomizedDelaySec=30min
```

`OnCalendar=` with an empty value resets the distro schedule before the new one.

## why not unattended full-upgrade

security patches are small, predictable and tested against the release. a
`dist-upgrade` can want to remove packages and wait for input, which produces a
half-upgraded box at the worst time. security only, manual full upgrades on a
schedule you chose.
