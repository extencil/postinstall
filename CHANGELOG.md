# changelog

all notable changes to this repo. format loosely follows keep a changelog,
versions follow semver for the scripts.

## [unreleased]

### added

- `ssh_prank` module: a bundled Paramiko decoy on tcp/22, target-host apt
  dependencies, bounded connections, private host key and sandboxed systemd
  service, with config, live audit checks and recovery documentation
- verification backlog for GitHub public-key import, access safety and
  disposable-host deployment evidence
- Haltman community links and a documented commit/push workflow using
  conventional commits, staged publication checks and remote verification

### changed

- real ssh defaults to tcp/1 across deployment, fail2ban, audit and docs;
  existing config values still win, and invalid port numbers abort before changes
- nftables port sets use comma-separated elements when multiple ports are set
- ssh socket and service restart together when configuration changes, and the
  audit detects additional effective sshd ports

## [0.1.0] - 2026-11-21

first version that actually deploys a box.

### added

- `debian13-postinstall.sh` entrypoint with `--config`, `--only`, `--skip`,
  `--dry-run`, `--list` and `--audit`
- modules: preflight, users, firewall, ssh, fail2ban, sysctl, updates, tools,
  shell, docker, python, node, go, cloudflared, warp, dotfiles, verify
- `audit/debian13-audit.sh` read-only report with ok/warn/fail and exit codes
- `config/postinstall.env.example` covering identity, access, modules, tokens
- docs tree: debian 13 notes, hardening, cloudflare, runtimes, shell, secrets,
  audit and a new vps checklist
- `AGENTS.md` as the canonical llm/harness contract, with `CLAUDE.md`,
  `GEMINI.md`, copilot, cursor and `llms.txt` pointers to it
- backups of every overwritten file under `/var/backups/postinstall`
- run log under `/var/log/postinstall`

### notes

- debian 13 only. ssh socket activation is handled, older releases are not.
- node, go, cloudflared, warp and dotfiles are disabled until configured.
- firewall is nftables only. ufw gets disabled if it was active.
