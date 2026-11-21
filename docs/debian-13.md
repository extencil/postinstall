# debian 13 notes

trixie. what bites on a fresh vps and why the scripts look the way they do.

## base image

most providers give you a minimal trixie image: root, no sudo user, maybe an
ssh key injected into `/root/.ssh/authorized_keys`, maybe cloud-init, maybe a
rescue console. `preflight` warns when cloud-init is present because it likes
to touch things on first boot.

`/etc/debian_version` says `13.x`. if it does not, the script refuses to run
unless `ALLOW_UNSUPPORTED=1`. do not casually override that: trixie moved sshd
to socket activation and the script handles it, older debian does not have the
same units.

## ssh is socket activated

since debian 13, `ssh.socket` is enabled and `ssh.service` is not. the listening
port is configured on the socket, not in `sshd_config`:

```ini
# /etc/systemd/system/ssh.socket.d/10-postinstall-port.conf
[Socket]
ListenStream=
ListenStream=1
```

the first empty `ListenStream` clears the distro value, then the second line
sets yours. the script writes this and restarts `ssh.socket`. existing sessions
survive a socket restart; new connections need the new port.

if you ever disable the socket and go back to `ssh.service`, remove the socket
drop-in or the next enable will do something confusing. one of the two, not
both.

## nftables, not ufw

trixie ships nftables, and docker on debian is already iptables-nft, so the
kernel side is nft either way. `ufw` is a friendly wrapper with its own opinions
about docker; the scripts write `/etc/nftables.conf` directly and stop ufw if it
is active.

`flush ruleset` in that file nukes every table at reload time, including the
ones docker and fail2ban added to the kernel. both re-add their rules when
restarted, which is why the firewall module restarts them after applying.

## time and updates

`systemd-timesyncd` is the default ntp client and is plenty for a vps. chrony is
the answer if you need tighter sync or a local ntp server.

`unattended-upgrades` runs through `apt-daily-upgrade.timer`, not cron. the
script writes a drop-in that keeps debian and debian-security origins, no
automatic reboot, and lets `needrestart` do its thing after upgrades.

## apparmor

enabled by default in trixie, profiles for common daemons load on demand. the
audit only checks that the kernel side is on. per-service profiles are a
different rabbit hole.

## kernel and firmware

debian's cloud kernel is fine on kvm. on real hardware or weird virtio setups,
backports may have newer drivers:

```bash
echo "deb http://deb.debian.org/debian trixie-backports main" \
  | sudo tee /etc/apt/sources.list.d/backports.list
```

the scripts do not add backports. pinning a kernel from there is a decision for
the person who has to debug it.

## things the scripts will not fix for you

- provider firewall rules outside the box (security groups, network acls)
- ipv6 addressing and routing
- reverse dns
- the fact that the provider console is the only way back in after a bad sshd
  config
