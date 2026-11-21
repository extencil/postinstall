# copilot instructions

full contract: `AGENTS.md`. this file is the condensed copy for tools that do
not follow imports.

## project

shell scripts that harden a fresh debian 13 vps. `debian13-postinstall.sh`
applies, `audit/debian13-audit.sh` verifies (read only). modules live in
`lib/modules/` and are sourced in a fixed order by the entrypoint. config is
`config/postinstall.env` (gitignored), example committed.

bash 5, systemd, apt. no package, no build, no ci, no tests.

## rules

- idempotent and non-interactive. rerun equals no-op.
- mutating commands only through `run()`. config writes only through
  `write_file`, which backs up to `/var/backups/postinstall` first.
- new module touches all seven: module file, entrypoint `case` arm, config
  default, config example, README row, topic doc, audit check, changelog.
- never weaken the ssh lockout guard. no key + no password must abort.
- no `PasswordAuthentication yes`, `PermitRootLogin yes` or open firewall
  defaults.
- no secrets, tokens or real hostnames in the repo.
- no new runtime dependencies. apt, coreutils, systemd only.

## gates

```bash
for f in debian13-postinstall.sh audit/*.sh lib/common.sh lib/modules/*.sh; do
  bash -n "$f" || exit 1
done
shellcheck -x debian13-postinstall.sh lib/common.sh lib/modules/*.sh audit/*.sh
bash debian13-postinstall.sh --list
bash debian13-postinstall.sh --help
```

full `--dry-run` only in a disposable debian 13 vm. never on a real host.

## gotchas

- debian 13 ssh port lives in `ssh.socket` drop-in.
- sshd `00-` drop-in must stay first; cloud-init `50-` re-enables passwords.
- `flush ruleset` removes docker and fail2ban rules; restart both after.
- docker published ports bypass the input chain.
- `ip_forward` / ipv6 `accept_ra` are intentionally not in sysctl.
- fail2ban needs `backend = systemd` on trixie.
