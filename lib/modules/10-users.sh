#!/usr/bin/env bash
# module: users - the human account, its key, sudo rights, locked root.

module_users() {
  log_step "user and sudo"

  install_pkgs sudo

  if id -u "$NEW_USER" >/dev/null 2>&1; then
    log_skip "user $NEW_USER exists"
  else
    run adduser --disabled-password --gecos "" "$NEW_USER"
    log_ok "created $NEW_USER"
  fi

  if id -nG "$NEW_USER" | tr ' ' '\n' | grep -qx sudo; then
    log_skip "$NEW_USER already in sudo"
  else
    run usermod -aG sudo "$NEW_USER"
    log_ok "$NEW_USER -> sudo group"
  fi

  local sudoers=/etc/sudoers.d/90-postinstall-"$NEW_USER"
  if [[ ${SUDO_NOPASSWD:-0} == 1 ]]; then
    write_file "$sudoers" 0440 <<EOF
# managed by postinstall
$NEW_USER ALL=(ALL) NOPASSWD:ALL
EOF
  elif [[ -f $sudoers ]]; then
    run rm -f "$sudoers"
    log_ok "removed $sudoers (password prompt back on)"
  fi
  if [[ -f $sudoers ]]; then
    run visudo -cf "$sudoers" >/dev/null
  fi

  local home=/home/$NEW_USER
  local keys=$home/.ssh/authorized_keys
  local src=${SSH_PUBKEY_FILE:-/root/.ssh/authorized_keys}

  ensure_dir "$home/.ssh" 0700
  if [[ -s $src ]]; then
    if [[ -f $keys ]] && cmp -s "$src" "$keys"; then
      log_skip "$keys already up to date"
    else
      run install -m 0600 -o "$NEW_USER" -g "$NEW_USER" "$src" "$keys"
      log_ok "installed ssh key(s) for $NEW_USER from $src"
    fi
  elif [[ -n ${SSH_PUBKEY:-} ]]; then
    printf '%s\n' "$SSH_PUBKEY" | write_file "$keys" 0600
    run chown "$NEW_USER:$NEW_USER" "$keys"
    log_ok "installed ssh key from SSH_PUBKEY"
  elif [[ -s $keys ]]; then
    log_skip "$keys exists, leaving it alone"
  else
    log_warn "no ssh key found for $NEW_USER (checked $src)"
    log_warn "set SSH_PUBKEY_FILE or you will lock yourself out when ssh hardening runs"
  fi
  run chown -R "$NEW_USER:$NEW_USER" "$home/.ssh"
  run chmod 0700 "$home/.ssh"
  [[ -f $keys ]] && run chmod 0600 "$keys"

  # root stays usable through sudo, not through a password over ssh.
  if [[ $(passwd -S root 2>/dev/null | awk '{print $2}') == L ]]; then
    log_skip "root password already locked"
  else
    run passwd -l root
    log_ok "locked root password"
  fi
}
