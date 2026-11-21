# new vps checklist

provider day. ten minutes, no thinking required.

## before you run anything

- [ ] note the provider console url, you will need it if ssh breaks
- [ ] copy the public key into `SSH_PUBKEY_FILE` or make sure the provider
      injected one into `/root/.ssh/authorized_keys`
- [ ] pick the new user name and ssh port in the config
- [ ] decide cloudflare: named tunnel, mesh connector, both, none
- [ ] put tokens in `/root/.secrets/*.token` with `chmod 600`
- [ ] `config/postinstall.env` exists, `chmod 600`, not in git

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
