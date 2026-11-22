# tooling

apt-only, no installation scripts. the list is boring on purpose: things that
are already packaged and do not need a version manager.

## base

| package | for |
| --- | --- |
| `git`, `curl`, `wget`, `ca-certificates`, `gnupg` | getting things, verifying things |
| `jq` | reading api responses without python |
| `unzip`, `zip`, `tar`, `xz-utils`, `zstd` | archives |
| `tmux` | the session that survives a dropped ssh connection |
| `less`, `vim`, `nano` | editing over ssh |
| `htop`, `btop`, `ncdu`, `tree` | seeing what is eating the box |
| `rsync` | copying, resuming, excluding |
| `lsof`, `file`, `psmisc`, `procps` | the "what is this process" kit |
| `ripgrep` | grep that respects .gitignore |
| `fd-find`, `bat` | find and cat, with colors |
| `bind9-dnsutils`, `mtr-tiny`, `whois`, `netcat-openbsd` | network triage |
| `shellcheck` | linting these scripts on the box itself |

## the debian renames

debian installs `bat` as `batcat` and `fd` as `fdfind` to avoid clashing with
old packages. the tools module symlinks them into `/usr/local/bin`:

```bash
/usr/local/bin/bat -> /usr/bin/batcat
/usr/local/bin/fd  -> /usr/bin/fdfind
```

dotfiles that call `bat` work without a wrapper. the symlink is created only if
the target exists and the name is free.

## zsh

`zsh` is installed and set as the login shell for `NEW_USER`. no rc file is
written: that belongs to the dotfiles repo, and two systems writing `.zshrc` is
a support ticket waiting to happen.

if the dotfiles module is off, you get a bare zsh with debian's defaults. fine
for a server, boring for a human.

for a ready-to-try prompt, fuzzy search and both kali-style plugins, see the
[daily Zsh profile](zsh-profile.md).

## what i do not install

`docker-compose` v1, `node` from a tarball, `oh-my-zsh` from curl, `powerlevel10k`
from git, `neofetch` for the screenshot. the first four are maintenance debt, the
last one is a screenshot.

## verifying

```bash
dpkg -l | grep -E 'ripgrep|fd-find|bat|tmux'
shellcheck -x debian13-postinstall.sh lib/common.sh lib/modules/*.sh
bat --version && fd --version
```
