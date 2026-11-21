#!/usr/bin/env bash
# module: warp - cloudflare mesh connector (warp-cli), not the consumer vpn.
# upstream has no trixie repo; the bookworm package pulls in its own deps.

module_warp() {
  log_step "cloudflare mesh (warp connector)"

  if ! command -v warp-cli >/dev/null 2>&1; then
    ensure_dir /usr/share/keyrings 0755
    if [[ ! -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg ]]; then
      run curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
      run chmod a+r /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    fi
    write_file /etc/apt/sources.list.d/cloudflare-client.list 0644 <<EOF
deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${WARP_CODENAME:-bookworm} main
EOF
    refresh_apt
    install_pkgs cloudflare-warp
    run systemctl enable --now warp-svc
  else
    log_skip "warp-cli present"
  fi

  # already registered and connected: a rerun must not need the token again.
  local status_line=""
  status_line=$(warp-cli --accept-tos status 2>/dev/null | head -1 || true)
  if grep -qi connected <<<"$status_line"; then
    log_skip "warp already: $status_line"
    return 0
  fi

  local token=""
  if [[ -n ${CLOUDFLARE_WARP_TOKEN_FILE:-} ]]; then
    [[ -r $CLOUDFLARE_WARP_TOKEN_FILE ]] || die "CLOUDFLARE_WARP_TOKEN_FILE is not readable"
    token=$(tr -d '\r\n' <"$CLOUDFLARE_WARP_TOKEN_FILE")
  elif [[ -n ${CLOUDFLARE_WARP_TOKEN:-} ]]; then
    token=$CLOUDFLARE_WARP_TOKEN
  fi

  if [[ -z $token ]]; then
    log_warn "no CLOUDFLARE_WARP_TOKEN(_FILE). package installed, connector not registered"
    log_info "zero trust > networks > tunnels > create a warp connector, copy the token"
    return 0
  fi

  if ((DRY_RUN)); then
    log_dry "warp-cli --accept-tos connector new <token>"
    return 0
  fi

  # connector mode is what mesh expects. registration token is the older
  # client flow, kept as a fallback for accounts still on it.
  if warp-cli --accept-tos connector new "$token" 2>/dev/null; then
    log_ok "warp connector registered"
  elif warp-cli --accept-tos registration token "$token" 2>/dev/null; then
    warp-cli --accept-tos connect
    log_ok "warp client registered and connected"
  else
    log_warn "warp-cli rejected the token. check it in the dashboard, then rerun"
    return 0
  fi

  run systemctl enable --now warp-svc
  log_info "status: $(warp-cli --accept-tos status 2>/dev/null | head -1)"
}
