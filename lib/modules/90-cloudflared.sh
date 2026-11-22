#!/usr/bin/env bash
# module: cloudflared - remotely managed tunnel, host service, outbound only.

module_cloudflared() {
  log_step "cloudflared"

  install_pkgs curl ca-certificates
  ensure_dir /usr/share/keyrings 0755

  local repo_changed=0
  if [[ ! -s /usr/share/keyrings/cloudflare-main.gpg ]]; then
    run curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
      -o /usr/share/keyrings/cloudflare-main.gpg
    run chmod a+r /usr/share/keyrings/cloudflare-main.gpg
    repo_changed=1
    log_ok "cloudflare apt key installed"
  else
    log_skip "cloudflare apt key present"
  fi

  write_file /etc/apt/sources.list.d/cloudflared.list 0644 <<'EOF'
deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main
EOF
  [[ $LAST_WRITE_CHANGED == 1 ]] && repo_changed=1

  if [[ $repo_changed == 1 ]] || ! pkg_installed cloudflared; then
    refresh_apt
  fi
  install_pkgs cloudflared

  # a service created by `cloudflared service install` already carries its
  # token. reruns restart it if needed and never ask for the token again.
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
    case $(stat -c '%a' "$CLOUDFLARED_TOKEN_FILE") in
      400 | 600) ;;
      *) die "CLOUDFLARED_TOKEN_FILE must be mode 0400 or 0600: $CLOUDFLARED_TOKEN_FILE" ;;
    esac
    token=$(tr -d '\r\n' <"$CLOUDFLARED_TOKEN_FILE")
  elif [[ -n ${CLOUDFLARED_TOKEN:-} ]]; then
    token=$CLOUDFLARED_TOKEN
  fi

  if [[ -z $token ]]; then
    log_warn "no CLOUDFLARED_TOKEN(_FILE). binary installed, tunnel not configured"
    log_info "dashboard: zero trust > networks > tunnels > create > debian 64-bit"
    log_info "name the tunnel after this host: $(hostname -s 2>/dev/null || hostname)"
    return 0
  fi

  # writes the service unit and /etc/cloudflared/token (0600); the unit points
  # at that file with --token-file. the source file is only needed on install.
  if ((DRY_RUN)); then
    log_dry "cloudflared service install <token>"
  else
    run cloudflared service install "$token" >/dev/null
    log_ok "cloudflared tunnel service installed"
    run systemctl enable --now cloudflared
  fi

  if ((DRY_RUN == 0)); then
    service_active cloudflared || die "cloudflared service failed to start; check journalctl -u cloudflared"
  fi
}
