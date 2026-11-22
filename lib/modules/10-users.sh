#!/usr/bin/env bash
# module: users - the human account, its key, sudo rights, locked root,
# and the provider's default account put out of reach.

module_users() {
  log_step "user and sudo"

  install_pkgs sudo openssl adduser

  if id -u "$NEW_USER" >/dev/null 2>&1; then
    log_skip "user $NEW_USER exists"
  else
    run adduser --disabled-password --gecos "" "$NEW_USER"
    log_ok "created $NEW_USER"
  fi

  # A key-only login needs a local password for sudo. An explicit
  # NEW_USER_PASSWORD wins; otherwise NEW_USER_PASSWORD_FILE is read when it
  # exists, and only a missing file is generated. The file is the recommended
  # path: it keeps SSH key-only and still gives the human a sudo credential.
  local password_status password_file password generated=0
  password_status=$(passwd -S "$NEW_USER" 2>/dev/null | awk '{print $2}' || true)
  password_file=${NEW_USER_PASSWORD_FILE:-/root/postinstall-$NEW_USER.password}
  [[ $password_file == /* ]] || password_file=$ROOT_DIR/$password_file
  if [[ -z ${NEW_USER_PASSWORD:-} && -s $password_file ]]; then
    case $(stat -c '%a' "$password_file") in
      400 | 600) ;;
      *) die "NEW_USER_PASSWORD_FILE must be mode 0400 or 0600: $password_file" ;;
    esac
  fi
  if [[ $password_status == P ]]; then
    log_skip "$NEW_USER already has a password"
  else
    if [[ -n ${NEW_USER_PASSWORD:-} ]]; then
      password=$NEW_USER_PASSWORD
      log_info "using NEW_USER_PASSWORD from config"
    elif [[ -s $password_file ]]; then
      password=$(<"$password_file")
      log_info "using chosen password from $password_file"
    else
      password=$(openssl rand -hex 32 2>/dev/null || printf 'dry-run-password')
      ((DRY_RUN)) || [[ $password != dry-run-password ]] || die "openssl failed to generate a password"
      generated=1
    fi
    [[ -n $password ]] || die "empty password for $NEW_USER"
    [[ $password != *:* && $password != *$'\n'* ]] || die "password for $NEW_USER must not contain ':' or a newline"
    if ((generated)); then
      ensure_dir "$(dirname "$password_file")" 0700
      write_file "$password_file" 0600 <<<"$password"
      log_ok "generated password stored in $password_file (0600)"
      if [[ ${SUDO_NOPASSWD:-0} != 1 ]]; then
        log_warn "sudo needs this generated password; read it as root from the provider console"
        log_warn "or put your chosen password in NEW_USER_PASSWORD_FILE before the first run"
      fi
    fi
    run chpasswd <<<"$NEW_USER:$password"
    log_ok "set password for $NEW_USER"
    unset password
  fi

  if id -nG "$NEW_USER" 2>/dev/null | tr ' ' '\n' | grep -qx sudo; then
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

  local home keys src="" inline=0 have_key=0
  home=$(getent passwd "$NEW_USER" | cut -d: -f6 || true)
  if [[ -z $home ]]; then
    if ((DRY_RUN)); then
      home=/home/$NEW_USER
    else
      die "cannot resolve home directory for $NEW_USER"
    fi
  fi
  keys=$home/.ssh/authorized_keys

  if [[ -n ${SSH_PUBKEY:-} ]]; then
    src=inline
    inline=1
  elif [[ -n ${SSH_PUBKEY_FILE:-} ]]; then
    src=$SSH_PUBKEY_FILE
    [[ $src == /* ]] || src=$ROOT_DIR/$src
    [[ -r $src && -s $src ]] || die "SSH_PUBKEY_FILE is set but unreadable or empty: $src"
  elif [[ -s $keys ]]; then
    src=""
    log_skip "$keys exists, leaving it alone"
  else
    src=/root/.ssh/authorized_keys
  fi

  ensure_dir "$home/.ssh" 0700
  if [[ $inline == 1 ]]; then
    if [[ $SSH_PUBKEY =~ (^|[[:space:]])(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[^[:space:]]+|sk-ssh-[^[:space:]]+)[[:space:]]+AAAA ]]; then
      if [[ -f $keys ]] && [[ "$(<"$keys")" == "$SSH_PUBKEY" ]]; then
        log_skip "$keys already up to date"
      else
        write_file "$keys" 0600 <<<"$SSH_PUBKEY"
        log_ok "installed ssh key from SSH_PUBKEY"
      fi
    else
      die "SSH_PUBKEY does not look like an ssh public key"
    fi
  elif [[ -n $src && -s $src ]]; then
    if ! grep -Eq '(^|[[:space:]])(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[^[:space:]]+|sk-ssh-[^[:space:]]+)[[:space:]]+AAAA' "$src"; then
      die "no usable ssh public key in $src"
    fi
    if [[ -f $keys ]] && [[ "$(<"$src")" == "$(<"$keys")" ]]; then
      log_skip "$keys already up to date"
    else
      write_file "$keys" 0600 <"$src"
      log_ok "installed ssh key(s) for $NEW_USER from $src"
    fi
  elif [[ -s $keys ]]; then
    log_skip "$keys exists, leaving it alone"
  else
    log_warn "no ssh key found for $NEW_USER (checked $src)"
    log_warn "set SSH_PUBKEY_FILE or you will lock yourself out when ssh hardening runs"
  fi

  if [[ -d $home/.ssh ]]; then
    if [[ $(stat -c '%U:%G' "$home/.ssh") != "$NEW_USER:$NEW_USER" ]]; then
      run chown "$NEW_USER:$NEW_USER" "$home/.ssh"
      log_ok "$home/.ssh -> $NEW_USER"
    fi
    if [[ $(stat -c '%a' "$home/.ssh") != 700 ]]; then
      run chmod 0700 "$home/.ssh"
      log_ok "$home/.ssh -> 0700"
    fi
  fi
  if [[ -f $keys ]]; then
    have_key=1
    if [[ $(stat -c '%U:%G' "$keys") != "$NEW_USER:$NEW_USER" ]]; then
      run chown "$NEW_USER:$NEW_USER" "$keys"
      log_ok "$keys -> $NEW_USER"
    fi
    if [[ $(stat -c '%a' "$keys") != 600 ]]; then
      run chmod 0600 "$keys"
      log_ok "$keys -> 0600"
    fi
  fi

  if [[ ${SUDO_NOPASSWD:-0} != 1 && -z ${NEW_USER_PASSWORD:-} ]]; then
    log_info "sudo asks for the password in $password_file"
  fi

  # root stays usable through sudo, not through a password over ssh.
  if [[ $(passwd -S root 2>/dev/null | awk '{print $2}' || true) == L ]]; then
    log_skip "root password already locked"
  else
    run passwd -l root
    log_ok "locked root password"
  fi

  # Providers ship debian/ubuntu accounts with a guessable name and sometimes
  # cloud-init sudo rights. Disable them only after the replacement can log in.
  local -a disabled=()
  local disabled_list=${DISABLE_DEFAULT_USERS:-}
  read -r -a disabled <<<"${disabled_list//,/ }"
  ((${#disabled[@]})) || return 0

  local replacement_ready=0
  if [[ $have_key == 1 ]] &&
     grep -Eq '(^|[[:space:]])(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[^[:space:]]+|sk-ssh-[^[:space:]]+)[[:space:]]+AAAA' "$keys"; then
    replacement_ready=1
  elif ((DRY_RUN)) && [[ $inline == 1 || -s ${src:-} ]]; then
    replacement_ready=1
  elif [[ ${SSH_ALLOW_PASSWORD:-0} == 1 ]]; then
    replacement_ready=1
  fi

  if ((replacement_ready == 0)); then
    log_warn "not disabling ${disabled[*]}: $NEW_USER has no usable ssh key and SSH_ALLOW_PASSWORD=0"
    log_warn "the old account stays usable until ssh hardening aborts or you fix the key"
    return 0
  fi

  local u g expire f tmp main_grant
  for u in "${disabled[@]}"; do
    if [[ $u == root ]]; then
      log_warn "refusing to disable root, fix DISABLE_DEFAULT_USERS"
      continue
    fi
    [[ $u != "$NEW_USER" ]] || die "DISABLE_DEFAULT_USERS contains NEW_USER=$NEW_USER"
    if ! id -u "$u" >/dev/null 2>&1; then
      log_skip "default account $u not present"
      continue
    fi
    local disabled_changed=0

    for g in sudo docker; do
      if getent group "$g" >/dev/null 2>&1 && id -nG "$u" | tr ' ' '\n' | grep -qx "$g"; then
        run usermod -rG "$g" "$u"
        log_ok "$u removed from $g"
        disabled_changed=1
      fi
    done

    if [[ $(getent passwd "$u" | cut -d: -f7) != /usr/sbin/nologin ]]; then
      run usermod -s /usr/sbin/nologin "$u"
      log_ok "$u shell -> nologin"
      disabled_changed=1
    fi

    if [[ $(passwd -S "$u" 2>/dev/null | awk '{print $2}' || true) != L ]]; then
      run usermod -L "$u"
      log_ok "locked $u password"
      disabled_changed=1
    fi

    expire=$(awk -F: -v name="$u" '$1 == name { print $8 }' /etc/shadow 2>/dev/null || true)
    if [[ -z $expire || $expire == 0 ]]; then
      run chage -E 1 "$u"
      log_ok "expired $u account"
      disabled_changed=1
    fi

    if command -v loginctl >/dev/null 2>&1 &&
       loginctl list-users --no-legend 2>/dev/null | awk '{print $2}' | grep -qx "$u"; then
      run loginctl terminate-user "$u"
      log_ok "terminated $u sessions"
      disabled_changed=1
    fi
    if command -v pgrep >/dev/null 2>&1 && pgrep -u "$u" >/dev/null 2>&1; then
      run pkill -KILL -u "$u"
      log_ok "killed remaining $u processes"
      disabled_changed=1
    fi

    # cloud-init writes 90-cloud-init-users with NOPASSWD. group removal alone
    # does not revoke that, so scrub lines that name the account.
    for f in /etc/sudoers.d/*; do
      [[ -f $f ]] || continue
      grep -qE "^[[:space:]]*${u}[[:space:]]" "$f" || continue
      tmp=$(mktemp)
      grep -vE "^[[:space:]]*${u}[[:space:]]" "$f" >"$tmp" || true
      write_file "$f" 0440 <"$tmp"
      rm -f "$tmp"
      run visudo -cf "$f" >/dev/null
      log_ok "removed $u sudo grant from $f"
      disabled_changed=1
    done

    main_grant=$(grep -lE "^[[:space:]]*${u}[[:space:]]" /etc/sudoers 2>/dev/null || true)
    if [[ -n $main_grant ]]; then
      log_warn "$u still has a grant in /etc/sudoers, remove it by hand"
    fi
    if ((disabled_changed == 0)); then
      log_skip "$u already disabled"
    fi
  done
}
