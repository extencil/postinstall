#!/usr/bin/env bash
# module: fail2ban - reads the journal, bans into its own nft table.

module_fail2ban() {
  log_step "fail2ban"

  install_pkgs fail2ban python3-systemd

  # nftables actions exist since 1.x. older packages fall back to iptables-nft,
  # which on debian is the same kernel backend anyway.
  local banaction=iptables-multiport
  if [[ -f /etc/fail2ban/action.d/nftables-multiport.conf ]]; then
    banaction=nftables-multiport
  else
    log_warn "no nftables action in this fail2ban, using $banaction (still nft under the hood)"
  fi

  write_file /etc/fail2ban/jail.d/postinstall.local 0644 <<EOF
# managed by postinstall - edit the script, not this file
[DEFAULT]
backend = systemd
banaction = $banaction
banaction_allports = ${banaction%-multiport}-allports
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${SSH_PORT:-22}
mode = aggressive
EOF

  if ! run fail2ban-client -t >/dev/null 2>&1; then
    log_warn "fail2ban config test complained, check /etc/fail2ban/jail.d/postinstall.local"
  fi

  if [[ $LAST_WRITE_CHANGED == 1 ]] || ! service_active fail2ban; then
    enable_now fail2ban
    run systemctl restart fail2ban
    log_ok "fail2ban running, sshd jail on port ${SSH_PORT:-22}"
  else
    log_skip "fail2ban already running"
  fi
}
