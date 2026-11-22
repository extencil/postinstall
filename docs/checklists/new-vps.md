# new vps checklist

provider day. ten minutes, no thinking required.

## before you run anything

- [ ] note the provider console url, you will need it if ssh breaks
- [ ] copy the public key into `SSH_PUBKEY_FILE` or `SSH_PUBKEY` (or make sure
      the provider injected one into `/root/.ssh/authorized_keys`)
- [ ] pick the new user name and ssh port in the config (`1/tcp` by default)
- [ ] leave `DISABLE_DEFAULT_USERS=debian` so the provider account is neutered
- [ ] leave `NEW_USER_PASSWORD` and `NEW_USER_PASSWORD_FILE` empty. the host
      generates a root-only password; read it from the root session, then
      change it with `passwd` if you want. SSH stays public-key only.
- [ ] allow real ssh at the provider firewall
- [ ] decide cloudflare: named tunnel or none
- [ ] put tokens in `/root/.secrets/*.token` with `chmod 600`
- [ ] `config/postinstall.env` exists, `chmod 600`, not in git

## staged first host (POC)

do this on one disposable or least critical host before the other five. keep the
provider console open and never close the current root session until the new
login is proven.

phase 1, keep the old account and root password:

```bash
sudo bash debian13-postinstall.sh --dry-run
sudo bash debian13-postinstall.sh --only preflight,users,firewall,ssh \
  --keep-default-users --keep-root-password
```

prove from a second terminal:

```bash
ssh -p 1 extencil@host
sudo -v
docker run --rm hello-world     # if docker is enabled
```

phase 2, disable `debian` and lock root after the new login works:

```bash
sudo bash debian13-postinstall.sh --only users,ssh
getent passwd debian
passwd -S debian
sudo sshd -T | grep -E '^(allowusers|denyusers)'
```

phase 3, decoy and fail2ban:

```bash
sudo bash debian13-postinstall.sh --only firewall,ssh_prank,fail2ban
sudo bash audit/debian13-audit.sh
```

repeat on the next host only after phase 3 is clean and a reboot still lets you
in on `SSH_PORT`.

## run

```bash
sudo bash debian13-postinstall.sh --dry-run
sudo bash debian13-postinstall.sh
```

dry-run first on an image you have not seen before. it prints every file it
would write and every package it would install. no state changes.

## after

- [ ] open a second terminal, log in as `NEW_USER` on `SSH_PORT`
- [ ] `sudo -v` works
- [ ] `getent passwd debian` shows `nologin`, `passwd -S debian` shows `L`
- [ ] `sudo sshd -T | grep -E '^(allowusers|denyusers)'` shows only your user
- [ ] tcp/22 shows the prank banner and refuses authentication
- [ ] `sudo bash audit/debian13-audit.sh` says zero fails
- [ ] `docker run --rm hello-world` if docker is on
- [ ] `cloudflared` unit active and the dashboard shows the tunnel healthy
- [ ] `systemctl list-timers` shows apt-daily-upgrade
- [ ] reboot required? schedule it, do not ignore it forever
- [ ] remove the provider's rescue password or rotate it
- [ ] add the host to your inventory, backups and monitoring

## if you locked yourself out

existing ssh sessions keep working. do not close them.

1. from the live session, fix `/etc/ssh/sshd_config.d/00-postinstall.conf`
2. `sshd -t` must pass before any restart
3. on socket activation: `systemctl restart ssh.socket`
4. no live session left: provider console, or rescue mode, then edit the file
   and bring the box back

the audit and the firewall are both recoverable from a console. sshd config
mistakes are the common way to lose twenty minutes.

## decommission

for the host you are replacing, not the new one:

- [ ] revoke its ssh keys and tunnel tokens
- [ ] remove dns records and cloudflare routes
- [ ] delete the provider instance only after backups are verified
