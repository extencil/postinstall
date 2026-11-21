# changelog

all notable changes to this repo. format loosely follows keep a changelog,
versions follow semver for the scripts.

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
