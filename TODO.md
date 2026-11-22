# todo

pending work and things to prove on a disposable debian 13 box. unchecked means
unverified or not implemented. reading the script is not a successful login.

## daily zsh profile

- [ ] try the [Zsh profile](docs/shell/zsh-profile.md) over SSH and inside tmux
  from the usual terminal client. Check redraw, key chords, theme colors and
  second-login and rollback behavior.

## github ssh keys

idea: keep the private key where it already belongs. optionally fetch the
account's public authentication keys from `https://github.com/<username>.keys`
and install the selected keys for `NEW_USER` before ssh hardening runs.
uploading a key to github and configuring the account remain manual steps.

- [ ] add an opt-in github username setting, empty by default. document the
  `.keys` endpoint and use a placeholder username in examples.
- [ ] define source precedence alongside `SSH_PUBKEY_FILE`, `SSH_PUBKEY`, the
  root key fallback and an existing user key file. an explicitly selected
  source must not silently lose to the root fallback.
- [ ] decide whether to import all account keys or require selected fingerprints.
  document that importing all keys grants server access to every imported key.
- [ ] fetch over https with bounded connection and total timeouts. reject http
  errors, empty responses, html and malformed keys before touching access.
- [ ] validate each key with openssh tooling and deduplicate by key material.
  check the required tool is available before the users module needs it.
- [ ] use `write_file` for `authorized_keys`, with backups, correct ownership,
  mode `0600` and `.ssh` mode `0700`. preserve unrelated keys and their options;
  define how keys managed by this source are identified.
- [ ] keep a failed fetch from replacing existing keys. if no usable key remains,
  abort before disabling password or root ssh access.
- [ ] define rotation and revocation behavior on reruns. removing a key from
  github must not be described as removing it from a server automatically.
  no background synchronization unless explicitly configured later.
- [ ] route mutations through `run` and `write_file`. prove dry-run creates no
  files and changes no permissions or users.
- [ ] extend the read-only audit to validate installed keys, ownership and modes
  without needing github or a network connection.
- [ ] update entrypoint defaults, config example, ssh docs and changelog in the
  implementation change. preserve the existing lockout guard.
- [ ] verify one key, multiple keys, duplicates, malformed responses, timeout,
  empty account, rotation, existing local keys and a second unchanged run.
- [ ] prove login with the matching private key in a separate session before
  closing the provider shell. never copy a private key to the server or repo.

## ssh port 1 and port 22 decoy

accepted direction: real ssh on `1/tcp`, with a fake ssh
service on `22/tcp` to occupy automated scanners and brute-force clients.
the motivation is to reduce traffic aimed at the usual ssh ports, including
`22` and `2222`. implement and document this setup; keep deployment evidence
separate from local checks.

reference: [fake-ssh.py gist](https://gist.github.com/extencil/659287bc46c31d8d8ffb6fb90b7cddb7),
with a [pinned script revision](https://gist.githubusercontent.com/extencil/659287bc46c31d8d8ffb6fb90b7cddb7/raw/1d556673ee158489fef99fe46dc8e70b24e9afbc/fake-ssh.py).
these are source references. deployment support is implemented in this repo;
live deployment verification remains pending.

- [x] approve implementation and documentation, with real ssh defaulting to
  `1/tcp`. the owner approved the access-default change.
- [x] change ssh, firewall and fail2ban fallbacks, audit defaults and docs to
  port `1`. preserve explicit config and flag overrides.
- [x] keep dependencies on the target host: the module installs Debian's
  `python3-paramiko` through apt. no install or hardening of the developer's WSL.
- [x] review and adapt the decoy: cap connections, admission rate and session
  lifetime; avoid client-controlled logs; add a separate systemd identity,
  sandbox and resource limits. fail2ban continues watching real ssh only.
- [x] add the decoy module after real ssh moves, with defaults, runner mapping,
  config, read-only audit, docs and changelog. reject port conflicts before
  changes, open tcp/22 and never replace an unrelated listener.
- [x] use a separate systemd identity, a persistent private host key, a managed
  banner and bounded connections and session lifetimes. reject all logins,
  channels and forwarding; never log passwords or client keys.
- [x] pass local syntax checks, shellcheck, systemd unit verification and
  isolated regression checks with Debian 13's Paramiko package. protocol checks
  cover banner delivery, rejected authentication, connection limits and expiry;
  module checks use mocked mutations, not a live deploy.
- [ ] prove the full migration on a disposable Debian 13 host with systemd:
  verify the socket leaves tcp/22, real key login and sudo work on tcp/1,
  the decoy starts inside its sandbox, and a rerun changes nothing.
- [x] gather and review the screenshots at the repository root:
  shodan (`chrome_QO10xwv7vw.png`) and censys (`chrome_sXaWQ1kRaC.png`).
  these unredacted originals remain local and are excluded from publication.
  both show ports `25`, `80`, `443` and `587`; neither lists `1/tcp` or ssh
  in the visible host summary. neither screenshot shows a capture or scan date.
- [ ] redact real hostnames and addresses from both screenshots before
  committing them. the current files still contain those identifiers.
- [ ] record capture dates, search scope, scan timestamps and the approximate
  deployment date. the owner reports about three months without the real ssh
  service appearing in either index. the screenshots support the visible
  summaries, but do not establish the three-month history.
- [ ] distinguish a reachable ssh banner from index coverage. the owner supplied
  a successful connection to `1/tcp` with an openssh banner. absent search
  results only describe the observed results at capture time; they do not
  prove that nobody scanned, connected to or discovered that port.
- [ ] if published, frame the evidence as a dated observation about discovery
  and noise. do not claim that port `1` prevents reconnaissance or brute force.
- [x] cover the ssh socket drop-in, firewall
  allowance for real ssh and the decoy, audit expectations and console recovery.
  keep key authentication, the lockout guard and separate-session login checks.

## access and file handling

- [x] route the file-source branch in `10-users.sh` through `write_file`.
  inline and existing-key branches use it too.
- [x] verify the key-only user can actually use sudo with `SUDO_NOPASSWD=0`.
  container and first-VPS checks proved `sudo -S`/`sudo su root` accept the
  generated password; password was rotated afterwards.
- [x] strengthen the ssh lockout check beyond a nonempty `authorized_keys`.
  it now checks key material, owner, modes, effective home and that
  `SSH_ALLOW_USERS` permits the intended account.
- [x] verify the user's home through the account database. users and ssh use
  `getent passwd` instead of assuming `/home/$NEW_USER`.
- [ ] verify an unchanged rerun skips ownership changes, permission changes,
  daemon reloads and service restarts where state already matches. users
  module reruns are clean in a container; services still need a live host.
- [ ] verify invalid ssh configuration leaves a recoverable file on disk.
  `sshd -t` prevents a restart, but the drop-in has already been written.

## default account disable

- [x] prove on a fresh debian 13 image that `debian` ends with
  `/usr/sbin/nologin`, password `L`, a non-never expiry, no sudo/docker groups
  and no cloud-init sudoers grant.
- [x] prove sshd rejects `debian` with a key and with a password, including
  when provider cloud-init re-adds its drop-in after a reboot. the first-VPS
  audit after reboot still showed `denyusers debian`, no sudoers grant and
  `passwordauthentication no`.
- [ ] prove `users` refuses to disable the account when `NEW_USER` has no key
  and `SSH_ALLOW_PASSWORD=0`.
- [ ] prove a second identical run changes no password hash, key mode, sudoers
  file, account state or service on a live host.

## disposable host verification

first-VPS evidence: [2026-11-22](docs/verification/2026-11-22-first-vps.md).
service mode passed; socket mode and the other five hosts remain.

- [x] run syntax checks and shellcheck using the commands in `AGENTS.md`.
- [x] check `--help`, `--version`, `--list`, config precedence, `--only` and
  `--skip`. verify disabled optional modules stay disabled on a normal run.
- [x] inspect a root dry-run on a disposable debian 13 host. compare system
  state before and after, including logging and temporary files.
- [x] deploy on a fresh disposable host, then rerun with identical config.
  record actual changes, backups and restarts on both runs.
- [ ] verify ssh socket activation and service mode, including a port change,
  firewall rules and a successful new login on the configured port. service mode
  and a new login on tcp/1 passed on the first VPS; socket activation is pending.
- [ ] verify a firewall rewrite restores docker networking and fail2ban bans.
  check published docker ports separately from the host input policy.
- [ ] prove cloudflared with a real dashboard token: official apt repo, host
  unit active, `/etc/cloudflared/token` mode 0600, dashboard route changes
  apply without a restart.
- [ ] run the audit with and without root, with and without config. verify
  failures exit `1`, usage errors exit `2` and warnings alone exit `0`.
- [x] compare every enabled module's resulting state with its audit checks.
  record gaps instead of treating package presence as proof of configuration.
  first-VPS audit after reboot: 96 ok, 5 warn, 0 fail, 3 skip.
- [ ] document provider-console recovery using the backups from that run.
  keep results in the repo without real hostnames, addresses, keys or tokens.
