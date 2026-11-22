# changelog

all notable changes to this repo. format loosely follows keep a changelog,
versions follow semver for the scripts.

## [unreleased]

### added

- `--keep-default-users` and `--keep-root-password` for a staged first-host POC
  that proves the new key-only login before disabling `debian` or locking root
- `users` reads a chosen sudo password from `NEW_USER_PASSWORD_FILE`
  (`0400`/`0600`), falls back to `NEW_USER_PASSWORD`, and only generates a
  64-character password when neither exists; SSH stays public-key only
- `DISABLE_DEFAULT_USERS=debian` disables the provider account with a nologin
  shell, locked password, expiry, group removal, sudoers scrub and sshd
  `DenyUsers`, only after `NEW_USER` has a usable key
- `ssh` writes an effective `DenyUsers` line and filters disabled accounts out
  of `SSH_ALLOW_USERS`
- audit checks the generated password state, disabled-account shell/lock/expiry/
  groups/sudoers, effective `AllowUsers` / `DenyUsers` and key ownership
- `ssh_prank` module: a bundled Paramiko decoy on tcp/22, target-host apt
  dependencies, bounded connections, private host key and sandboxed systemd
  service, with config, live audit checks and recovery documentation
- verification backlog for GitHub public-key import, access safety and
  disposable-host deployment evidence
- Haltman community links and a documented commit/push workflow using
  conventional commits, staged publication checks and remote verification

### changed

- `cloudflared` now always ensures the official apt key and repository, installs
  the distro package, installs the host systemd service and verifies it started;
  dashboard routing changes stay hot
- the ssh lockout guard validates effective home, key material, ownership and
  modes, and requires `SSH_ALLOW_USERS` to permit `NEW_USER`
- `SSH_PUBKEY_FILE` honours relative paths, never silently loses to the root
  fallback, and `authorized_keys` writes go through `write_file`
- inline `SSH_PUBKEY` wins over `SSH_PUBKEY_FILE`; an explicitly selected
  source that is missing or malformed aborts instead of falling back
- real ssh defaults to tcp/1 across deployment, fail2ban, audit and docs;
  existing config values still win, and invalid port numbers abort before changes
- nftables port sets use comma-separated elements when multiple ports are set
- ssh socket and service restart together when configuration changes, and the
  audit detects additional effective sshd ports

### removed

- the `warp` module, `ENABLE_WARP`, its tokens and `WARP_CODENAME` are gone.
  cloudflared tunnels with dashboard-managed routing remain the supported path.

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
