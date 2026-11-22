# a daily shell on debian 13

The [Zsh profile](../../assets/shell/zsh/.zshrc) gives an existing Debian 13
account a two-line prompt, Git branch and exit status, history suggestions,
syntax highlighting and fuzzy navigation. It uses Debian packages and Zsh's
built-in prompt. The installer still leaves `.zshrc` to the account owner.

## try it in one session

Run this from the repository root on the Debian host, as the account that will
use the profile. Only the package commands need `sudo`. Skip the second package
transaction if all you want is the prompt, Tab completion and local history.

```bash
sudo apt-get update
sudo apt-get install -y zsh git zsh-autosuggestions zsh-syntax-highlighting
sudo apt-get install -y fzf zoxide fd-find bat eza direnv tmux iproute2
```

For a fresh checkout, run `git clone https://github.com/extencil/postinstall.git`
and `cd postinstall` as the target account.

```bash
(
  set -eu
  profile="${XDG_CONFIG_HOME:-$HOME/.config}/postinstall/zsh"
  install -d -m 0700 -- "$profile"
  if ! cmp -s -- assets/shell/zsh/.zshrc "$profile/.zshrc"; then
    zsh -n assets/shell/zsh/.zshrc
    install --backup=numbered -m 0600 -- assets/shell/zsh/.zshrc "$profile/.zshrc"
  fi
  env ZDOTDIR="$profile" zsh
)
```

`ZDOTDIR` points Zsh at the trial profile. The trial writes its history and
completion cache there. Your existing startup files stay in place. Run `exit`
to return to the invoking shell. Rerun the same block to update the installed
copy. It backs up the previous copy when the file changes.

For the IP field, start a session with the following command. The field shows
the source IPv4 selected for `192.0.2.1` and reports a `tun`, `tap` or `wg` device
if that route uses one. This is a local route lookup with a ten-second cache per
shell. Tunnel presence and public egress can differ from the selected route.

```bash
env POSTINSTALL_PROMPT_IP=1 ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/postinstall/zsh" zsh
```

## what to try

| action | result |
| --- | --- |
| `false` inside this repository | the prompt shows the branch and a red `[1]` |
| Tab and arrow keys on a partial path | a case-insensitive completion menu with multiple matches |
| type the start of a previous command, then press Up | history search by prefix |
| type a previous command and press Right at the end of the input | accept the gray history suggestion |
| `Ctrl+R`, `Ctrl+T`, `Alt+C` | fzf history, file and directory pickers |
| `Ctrl+/` inside the file picker | toggle the `batcat` preview |
| visit a directory, leave it, then type `z` followed by part of its name | zoxide jumps back to it |
| `ll`, `la`, `el` | listings and a two-level tree with `eza` installed |
| `tmux new-session -A -s work` | a session that survives an SSH disconnect |

The profile loads in an interactive terminal with a usable `TERM`. The
optional integrations load when their binaries are present. `direnv` needs
`direnv allow` after you review a project's `.envrc`. The prompt uses ordinary
Unicode line drawing. Font and terminal tab settings live on the client.
Debian 13 ships an fzf version that provides `fzf --zsh`. [Debian fzf package](https://packages.debian.org/trixie/fzf) · [fzf integration](https://github.com/junegunn/fzf#setting-up-shell-integration)

## keep it for new logins

For an account with the default `ZDOTDIR` and a free `~/.zshrc` path, link the
tested profile. `ln -sT` refuses to replace any existing file or link. If your
dotfiles already own that path, keep using the `ZDOTDIR` launcher until you
choose which configuration should own completion, key bindings and the prompt.

```bash
profile="${XDG_CONFIG_HOME:-$HOME/.config}/postinstall/zsh"
ln -sT -- "$profile/.zshrc" "$HOME/.zshrc"
getent passwd "$(id -un)" | cut -d: -f7
```

The postinstall `shell` module already selects Zsh for `NEW_USER`. On an
existing account that uses Bash, record the shell printed above before an
optional `chsh -s /usr/bin/zsh`. Keep the current session open while testing a
second SSH login. With the link active, Zsh uses `~/.zsh_history`; the trial
history stays in the profile directory.

To roll back the link, check its destination before unlinking it. If you also
changed the login shell, restore the path you recorded with `chsh -s PATH`.
`zsh -f` gives you a recovery shell that skips user startup files.

```bash
profile="${XDG_CONFIG_HOME:-$HOME/.config}/postinstall/zsh"
if [ "$(readlink -- "$HOME/.zshrc")" = "$profile/.zshrc" ]; then
  unlink -- "$HOME/.zshrc"
fi
```

## what came from kali

- The Kali skeleton uses a two-line prompt, Emacs bindings, menu completion,
  case-insensitive matching, history filters and two packaged plugins. The
  profile here uses those ideas with a native Zsh Git hook. Kali also has a
  prompt toggle, terminal titles and a conditional `command-not-found` hook
  in its skeleton. [Kali `.zshrc`](https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc)
- Kali's Zsh review caught a plugin changing the effective value of a shell
  option and a terminal-title quoting edge case. This profile leaves glob
  matching at the Zsh default, keeps the completion permission checks via
  `compinit -i`, and sources highlighting after completion and plugin widgets.
  Use `autoload -Uz compaudit; compaudit` from Zsh if a completion directory gets
  skipped. [Kali review](https://gitlab.com/kalilinux/packages/kali-defaults/-/issues/2) · [Zsh completion manual](https://zsh.sourceforge.io/Doc/Release/Completion-System.html) · [highlighting load order](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md)
- Kali tracked the virtualenv prompt prefix breaking the layout. The profile
  disables the activation script's prefix and displays the environment name
  in the first line. [Kali virtualenv report](https://gitlab.com/kalilinux/packages/kali-defaults/-/issues/5)
- Kali also tracked plugin packages missing from minimal installations. The
  package command asks for both plugins explicitly. fzf owns `Ctrl+R`, and Zsh
  owns the local history file. [Kali package report](https://gitlab.com/kalilinux/packages/kali-tweaks/-/issues/25)

For more helpers, run `dpkg -L zsh-common` to see the completions and functions
Debian ships. Try `autoload -Uz zmv` followed by `zmv -n '(*).jpeg' '$1.jpg'`
to preview a batch rename.

## when something misbehaves

- For missing colors or keys over SSH or tmux, run `infocmp "$TERM"` and
  `bindkey` in the affected session. If the terminal type is unknown, install
  its terminfo entry on the Debian host or use a client profile with a terminal
  type Debian already knows.
- If `Ctrl+R` opens another picker, run `bindkey '^R'` and check the active rc
  file with `print -r -- "${ZDOTDIR:-$HOME}/.zshrc"`. In this profile the
  widget is `fzf-history-widget`. Start a fresh trial shell after changes so
  its widgets and hooks get loaded once.
- If the prompt or completion breaks, compare with `zsh -f` in the same
  terminal. Reproduce in the trial profile before linking it into a login.
