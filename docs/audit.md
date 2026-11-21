# audit

`audit/debian13-audit.sh` reads the box and reports. it never writes, never
restarts anything, never fixes a thing. the postinstall verify step runs it at
the end, cron can run it later.

## running

```bash
sudo bash audit/debian13-audit.sh
sudo bash audit/debian13-audit.sh --quiet
sudo bash audit/debian13-audit.sh --config config/postinstall.env
```

`--quiet` hides `ok` and `skip` lines, keeps warnings, failures, the score and
the exit code. that is the cron-friendly one.

exit codes:

| code | meaning |
| --- | --- |
| 0 | no failures (warnings allowed) |
| 1 | at least one check failed |
| 2 | bad flag or unreadable config |

## checks

| section | what it looks at |
| --- | --- |
| system | debian 13, systemd as pid 1, clock sync, pending reboot, apparmor |
| user and sudo | user exists, sudo and docker group, key file and modes, root locked |
| ssh | effective `sshd -T` values, drop-in present, listener on the port, password leftovers |
| firewall | nftables active, `table inet filter`, drop policies, ssh and extra ports |
| fail2ban | service, sshd jail, current and total bans |
| sysctl | every key in the deployed drop-in compared with the running kernel |
| updates | package, service, periodic config, apt timer |
| packages | the base toolset |
| runtimes | python, venv, pipx, uv; node and go when enabled |
| docker | service, `daemon.json` parses, the three daemon opinions, container count |
| cloudflare | `cloudflared` version and unit, warp status |
| listeners | world-facing tcp listeners, expected ssh port, count |
| dotfiles | clone present when `DOTFILES_REPO` is set |

it reads *effective* sshd config, so a drop-in that lost the ordering battle
fails even when the file on disk looks right. same for the firewall: it asks the
kernel, not the file.

## cron

```cron
17 7 * * * root /home/ops/postinstall/audit/debian13-audit.sh --quiet >/var/log/postinstall-audit.log 2>&1
```

mail on non-zero, or scrape the last line. `--quiet` still prints the score, so a
one-line check is enough.

if you run it as a non-root user, nftables, `sshd -T`, jail status and some file
checks are skipped instead of failing. full picture needs root.

## extending it

when a module starts changing state, add the matching check here in the same pr.
a check is one function call:

```bash
sysctl_is kernel.yama.ptrace_scope 1
unit_active cloudflared && ok "cloudflared active" || warn "cloudflared down"
```

keep checks read-only. no `systemctl restart`, no `nft add`, no package installs.
the audit is the thing you run when you are already unsure.

## what it cannot tell you

- whether the provider firewall is open or closed
- whether the ssh key in `authorized_keys` still exists on your laptop
- whether the tunnel token in the unit file is the current one
- whether a service is healthy, only whether it is running
- that the box is secure. it checks a known list of opinions, not every opinion.
