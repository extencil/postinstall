#!/usr/bin/env bash
# module: ssh_prank - a separate reject-only SSH decoy on port 22.

module_ssh_prank() {
  log_step "ssh prank (tcp/22)"

  [[ $SSH_PORT != 22 ]] || die "ssh prank needs real ssh on a different port"
  local unit=postinstall-ssh-prank.service listener real_listener pid line
  if ((DRY_RUN)); then
    log_dry "check real ssh on tcp/$SSH_PORT and exclusive decoy ownership of tcp/22"
  else
    # A failed migration must never be hidden by starting the decoy instead.
    real_listener=$(ss -Hltnp "sport = :$SSH_PORT")
    [[ -n $real_listener ]] || die "real ssh port $SSH_PORT has no listener"
    while IFS= read -r line; do
      [[ $line == *'("sshd"'* || $line == *'("systemd"'* ]] ||
        die "port $SSH_PORT is not owned by sshd or its systemd socket"
    done <<<"$real_listener"
    command -v sshd >/dev/null || die "real sshd is not installed"
    local ports
    ports=$(sshd -T | awk '$1 == "port" { print $2 }')
    [[ $ports == "$SSH_PORT" ]] || die "sshd has unexpected Port directives; fix them before deploying the decoy"
    listener=$(ss -Hltnp 'sport = :22')
    if [[ -n $listener ]]; then
      pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null || true)
      [[ $pid =~ ^[1-9][0-9]*$ ]] || die "tcp/22 belongs to another service; leaving it alone"
      # Check every listener, not just one of the address families.
      while IFS= read -r line; do
        [[ $line == *"pid=$pid,"* ]] || die "tcp/22 belongs to another service; leaving it alone"
      done <<<"$listener"
    fi
  fi

  local banner=${SSH_PRANK_BANNER_FILE:-$ROOT_DIR/assets/ssh-prank/banner.txt}
  [[ -r $banner && -s $banner ]] || die "ssh prank banner is missing or unreadable"
  [[ $(stat -c '%s' "$banner") -le 16384 ]] || die "ssh prank banner exceeds 16384 bytes"

  install_pkgs python3 python3-paramiko

  local changed=0 unit_changed=0
  write_file /usr/local/lib/postinstall/ssh-prank.py 0644 <"$ROOT_DIR/assets/ssh-prank/server.py"
  [[ $LAST_WRITE_CHANGED == 1 ]] && changed=1
  write_file /etc/postinstall/ssh-prank-banner.txt 0644 <"$banner"
  [[ $LAST_WRITE_CHANGED == 1 ]] && changed=1
  write_file /etc/systemd/system/postinstall-ssh-prank.service 0644 <<'EOF'
[Unit]
Description=Reject-only SSH decoy on port 22
After=network.target ssh.socket ssh.service
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
NotifyAccess=main
TimeoutStartSec=30
DynamicUser=yes
StateDirectory=postinstall-ssh-prank
StateDirectoryMode=0700
UMask=0077
ExecStart=/usr/bin/python3 -B /usr/local/lib/postinstall/ssh-prank.py --port 22 --key /var/lib/postinstall-ssh-prank/host_key --banner /etc/postinstall/ssh-prank-banner.txt
Restart=on-failure
RestartSec=5
TimeoutStopSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=yes
MemoryMax=192M
CPUQuota=50%
TasksMax=96
LimitNOFILE=256
StandardOutput=journal
StandardError=journal
LogRateLimitIntervalSec=60
LogRateLimitBurst=10

[Install]
WantedBy=multi-user.target
EOF
  if [[ $LAST_WRITE_CHANGED == 1 ]]; then
    changed=1
    unit_changed=1
  fi
  local path
  for path in /usr/local/lib/postinstall/ssh-prank.py /etc/postinstall/ssh-prank-banner.txt \
              /etc/systemd/system/postinstall-ssh-prank.service; do
    [[ -f $path ]] || continue
    if [[ $(stat -c '%u:%g' "$path") != 0:0 ]]; then
      run chown root:root "$path"
    fi
    if [[ $(stat -c '%a' "$path") != 644 ]]; then
      run chmod 0644 "$path"
    fi
  done
  if [[ $unit_changed == 1 ]]; then
    run systemctl daemon-reload
  fi
  if ! service_enabled "$unit"; then
    run systemctl enable "$unit"
  fi
  if [[ $changed == 1 ]]; then
    run systemctl restart "$unit"
    log_ok "ssh prank updated on tcp/22"
  elif ! service_active "$unit"; then
    run systemctl start "$unit"
    log_ok "ssh prank started on tcp/22"
  else
    log_skip "ssh prank unchanged"
  fi
  if ((DRY_RUN == 0)); then
    service_active "$unit" || die "ssh prank failed to start; check journalctl -u $unit"
  fi
}
