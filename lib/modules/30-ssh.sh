#!/usr/bin/env bash
# module: ssh - key only, no root login, one allowlist, drop-in that wins over cloud-init.

module_ssh() {
  log_step "ssh"

  install_pkgs openssh-server

  local home keys
  home=$(getent passwd "$NEW_USER" | cut -d: -f6 || true)
  if [[ -z $home ]]; then
    ((DRY_RUN)) || die "cannot resolve home directory for $NEW_USER"
    home=/home/$NEW_USER
  fi
  keys=$home/.ssh/authorized_keys
  if [[ ${SSH_ALLOW_PASSWORD:-0} != 1 ]]; then
    if [[ -s $keys ]]; then
      if ! grep -Eq '(^|[[:space:]])(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[^[:space:]]+|sk-ssh-[^[:space:]]+)[[:space:]]+AAAA' "$keys"; then
        die "no usable public key in $keys, refusing to disable password auth"
      fi
      [[ $(stat -c '%a' "$home/.ssh") == 700 ]] || die "$home/.ssh is not mode 700, sshd would ignore the key"
      [[ $(stat -c '%U' "$home/.ssh") == "$NEW_USER" ]] || die "$home/.ssh is not owned by $NEW_USER"
      [[ $(stat -c '%a' "$keys") == 600 ]] || die "$keys is not mode 600, sshd would ignore the key"
      [[ $(stat -c '%U' "$keys") == "$NEW_USER" ]] || die "$keys is not owned by $NEW_USER"
    elif ((DRY_RUN)); then
      log_dry "expect $keys after the users module"
    else
      die "no ssh key for $NEW_USER and SSH_ALLOW_PASSWORD=0 would lock you out. fix the key, or set SSH_ALLOW_PASSWORD=1"
    fi
  fi

  local -a requested=() disabled=()
  local allow_users="" deny_users="" u
  local disabled_list=${DISABLE_DEFAULT_USERS:-} requested_list=${SSH_ALLOW_USERS:-}
  read -r -a requested <<<"${requested_list//,/ }"
  read -r -a disabled <<<"${disabled_list//,/ }"
  for u in "${requested[@]}"; do
    if [[ " ${disabled[*]} " == *" $u "* ]]; then
      log_warn "ignoring disabled account $u in SSH_ALLOW_USERS"
      continue
    fi
    allow_users+="$u "
  done
  allow_users=${allow_users% }
  [[ -n $allow_users ]] || allow_users=$NEW_USER
  if [[ " $allow_users " != *" $NEW_USER "* && " $allow_users " != *" $NEW_USER@"* ]]; then
    die "SSH_ALLOW_USERS does not permit $NEW_USER, key-only login would be impossible"
  fi
  for u in "${disabled[@]}"; do
    [[ $u == root ]] && continue
    [[ $u == "$NEW_USER" ]] && die "DISABLE_DEFAULT_USERS contains NEW_USER=$NEW_USER"
    [[ " $deny_users " == *" $u "* ]] || deny_users+="$u "
  done
  deny_users=${deny_users% }

  local password_auth=no
  [[ ${SSH_ALLOW_PASSWORD:-0} == 1 ]] && password_auth=yes
  local tcp_forward=no
  [[ ${SSH_ALLOW_TCP_FORWARDING:-1} == 1 ]] && tcp_forward=yes
  local auth_methods=""
  [[ $password_auth == no ]] && auth_methods="AuthenticationMethods publickey"
  local deny_line=""
  [[ -n $deny_users ]] && deny_line="DenyUsers $deny_users"

  # 00- prefix: sshd takes the first value it sees, and this sorts before
  # 50-cloud-init.conf which loves re-enabling password auth.
  write_file /etc/ssh/sshd_config.d/00-postinstall.conf 0600 <<EOF
# managed by postinstall - edit the script, not this file
Port ${SSH_PORT:-1}
AddressFamily any

PermitRootLogin no
PasswordAuthentication $password_auth
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
$auth_methods

MaxAuthTries 3
MaxSessions 5
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2

X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding $tcp_forward
PermitTunnel no

UsePAM yes
LogLevel VERBOSE
$deny_line
AllowUsers $allow_users
EOF

  local ssh_changed=$LAST_WRITE_CHANGED

  if ((DRY_RUN)); then
    log_dry "sshd -t"
  elif ! sshd -t 2>/tmp/postinstall-sshd-test; then
    cat /tmp/postinstall-sshd-test >&2
    die "sshd config test failed, not restarting ssh"
  else
    log_ok "sshd config validates"
  fi

  # debian 13 ships ssh.socket enabled. the port lives in the socket unit,
  # so override ListenStream instead of fighting it.
  if service_enabled ssh.socket || service_active ssh.socket; then
    write_file /etc/systemd/system/ssh.socket.d/10-postinstall-port.conf 0644 <<EOF
[Socket]
ListenStream=
ListenStream=${SSH_PORT:-1}
EOF
    local socket_changed=$LAST_WRITE_CHANGED
    if [[ $socket_changed == 1 ]]; then
      run systemctl daemon-reload
    fi
    # Restart together: an active sshd can retain the old socket on port 22.
    if [[ $socket_changed == 1 || $ssh_changed == 1 ]] || ! service_active ssh.socket; then
      run systemctl restart ssh.socket ssh.service
      log_ok "ssh.socket and sshd updated on port ${SSH_PORT:-1}"
    else
      log_skip "ssh.socket and sshd unchanged"
    fi
  else
    if [[ $ssh_changed == 1 ]] || ! service_active ssh; then
      run systemctl restart ssh
      log_ok "sshd restarted on ${SSH_PORT:-1}"
    else
      log_skip "sshd unchanged"
    fi
    if ! service_enabled ssh; then
      run systemctl enable ssh
    fi
  fi

  if [[ ${SSH_PORT:-1} != 22 ]]; then
    log_warn "port moved to ${SSH_PORT}. old sessions survive, new ones need the new port"
    log_warn "keep this shell open until you proved login works on ${SSH_PORT}"
  fi
}
