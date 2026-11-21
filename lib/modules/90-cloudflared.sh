#!/usr/bin/env bash
# module: cloudflared - named tunnel, outbound only, zero inbound ports.

module_cloudflared() {
  log_step "cloudflared"

  if ! command -v cloudflared >/dev/null 2>&1; then
    ensure_dir /usr/share/keyrings 0755
    if [[ ! -f /usr/share/keyrings/cloudflare-main.gpg ]]; then
      run curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
      run chmod a+r /usr/share/keyrings/cloudflare-main.gpg
    fi
    write_file /etc/apt/sources.list.d/cloudflared.list 0644 <<'EOF'
deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main
EOF
    refresh_apt
    install_pkgs cloudflared
  else
    log_skip "cloudflared $(cloudflared --version 2>/dev/null | awk '{print $3}')"
  fi

  # a configured unit already carries its token, so reruns do not need the file.
  if [[ -f /etc/systemd/system/cloudflared.service ]] || systemctl cat cloudflared.service >/dev/null 2>&1; then
    if service_active cloudflared; then
      log_skip "cloudflared service already running"
    else
      run systemctl enable --now cloudflared
      log_ok "cloudflared service started"
    fi
    return 0
  fi

  local token=""
  if [[ -n ${CLOUDFLARED_TOKEN_FILE:-} ]]; then
    [[ -r $CLOUDFLARED_TOKEN_FILE ]] || die "CLOUDFLARED_TOKEN_FILE is not readable: $CLOUDFLARED_TOKEN_FILE"
    token=$(tr -d '\r\n' <"$CLOUDFLARED_TOKEN_FILE")
  elif [[ -n ${CLOUDFLARED_TOKEN:-} ]]; then
    token=$CLOUDFLARED_TOKEN
  fi

  if [[ -z $token ]]; then
    log_warn "no CLOUDFLARED_TOKEN(_FILE). binary installed, tunnel not configured"
    log_info "create one: cloudflare zero trust > networks > tunnels > create > debian"
    return 0
  fi

  # writes /etc/systemd/system/cloudflared.service and starts it.
  # the token ends up in the unit file, which is why it lives in a 0600 file.
  if ((DRY_RUN)); then
    log_dry "cloudflared service install <token>"
  else
    cloudflared service install "$token" >/dev/null
    log_ok "cloudflared tunnel service installed"
  fi
}
