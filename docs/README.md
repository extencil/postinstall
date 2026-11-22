# docs

reference material for the scripts. the scripts are the source of truth for
values, these files explain the reasoning, the failure modes and the parts i
will forget by the next provider.

- [debian 13 notes](debian-13.md)
- hardening
  - [ssh](hardening/ssh.md)
  - [ssh prank](hardening/ssh-prank.md)
  - [firewall](hardening/firewall.md)
  - [fail2ban](hardening/fail2ban.md)
  - [sysctl](hardening/sysctl.md)
  - [updates](hardening/updates.md)
- network
  - [cloudflare tunnel](network/cloudflare.md)
- runtimes
  - [docker](runtimes/docker.md)
  - [python](runtimes/python.md)
  - [node and go](runtimes/node-go.md)
- shell
  - [tooling](shell/tooling.md)
  - [daily Zsh profile](shell/zsh-profile.md)
- secrets
  - [dotfiles and secrets](secrets/dotfiles.md)
- [audit](audit.md)
- [new vps checklist](checklists/new-vps.md)
- verification
  - [first vps, 2026-11-22](verification/2026-11-22-first-vps.md)

adding a distro later: new entrypoint at the root, new `lib/modules` or a
distro prefix, new `docs/distro.md`. do not make the debian modules abstract
before a second distro exists. guessing abstractions is how these repos rot.
