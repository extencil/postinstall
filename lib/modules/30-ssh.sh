#!/usr/bin/env bash
# module: ssh - key only, no root login, drop-in that wins over cloud-init.

module_ssh() {
  log_step "ssh"

  install_pkgs openssh-server

  local keys=/home/$NEW_USER/.ssh/authorized_keys
  if [[ ! -s $keys ]] && [[ ${SSH_ALLOW_PASSWORD:-0} != 1 ]]; then
    die "no ssh key for $NEW_USER and SSH_ALLOW_PASSWORD=0 would lock you out. fix the key, or set SSH_ALLOW_PASSWORD=1"
  fi

  local allow_users=${SSH_ALLOW_USERS//,/ }
  [[ -n $allow_users ]] || allow_users=$NEW_USER
  local password_auth=no
  [[ ${SSH_ALLOW_PASSWORD:-0} == 1 ]] && password_auth=yes
  local tcp_forward=no
  [[ ${SSH_ALLOW_TCP_FORWARDING:-1} == 1 ]] && tcp_forward=yes
  local auth_methods=""
  [[ $password_auth == no ]] && auth_methods="AuthenticationMethods publickey"

  # 00- prefix: sshd takes the first value it sees, and this sorts before
  # 50-cloud-init.conf which loves re-enabling password auth.
  write_file /etc/ssh/sshd_config.d/00-postinstall.conf 0600 <<EOF
# managed by postinstall - edit the script, not this file
Port ${SSH_PORT:-22}
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
AllowUsers $allow_users
EOF

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
  if service_enabled ssh.socket; then
    write_file /etc/systemd/system/ssh.socket.d/10-postinstall-port.conf 0644 <<EOF
[Socket]
ListenStream=
ListenStream=${SSH_PORT:-22}
EOF
    run systemctl daemon-reload
    if [[ $LAST_WRITE_CHANGED == 1 ]] || ! service_active ssh.socket; then
      run systemctl restart ssh.socket
      log_ok "ssh.socket listening on ${SSH_PORT:-22}"
    else
      log_skip "ssh.socket unchanged"
    fi
  else
    if [[ $LAST_WRITE_CHANGED == 1 ]] || ! service_active ssh; then
      run systemctl restart ssh
      log_ok "sshd restarted on ${SSH_PORT:-22}"
    else
      log_skip "sshd unchanged"
    fi
    run systemctl enable ssh >/dev/null 2>&1 || true
  fi

  if [[ ${SSH_PORT:-22} != 22 ]]; then
    log_warn "port moved to ${SSH_PORT}. old sessions survive, new ones need the new port"
    log_warn "keep this shell open until you proved login works on ${SSH_PORT}"
  fi
}
