#!/usr/bin/env bash
# module: tools - the cli i reach for on every box. apt-only, no curl|bash.

module_tools() {
  log_step "base tools"

  install_pkgs \
    git curl wget ca-certificates gnupg \
    jq unzip zip tar xz-utils zstd \
    tmux less vim nano \
    htop btop ncdu tree rsync lsof file psmisc procps \
    ripgrep fd-find bat \
    bind9-dnsutils mtr-tiny whois netcat-openbsd \
    shellcheck

  # debian renames these to dodge the /usr/bin/bat and fd clashes.
  local link
  for link in "bat:/usr/bin/batcat" "fd:/usr/bin/fdfind"; do
    local name=${link%%:*} target=${link#*:}
    if [[ -x $target ]] && [[ ! -e /usr/local/bin/$name ]]; then
      run ln -s "$target" "/usr/local/bin/$name"
      log_ok "$name -> $target"
    fi
  done

  log_ok "tools ready"
}
