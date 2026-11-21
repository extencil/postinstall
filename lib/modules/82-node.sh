#!/usr/bin/env bash
# module: node - nodesource apt repo, pinned major. optional.

module_node() {
  log_step "node ${NODE_MAJOR:-24}.x"

  if command -v node >/dev/null 2>&1 && [[ $(node -v) == v${NODE_MAJOR:-24}.* ]]; then
    log_skip "node $(node -v) already installed"
    return 0
  fi

  ensure_dir /etc/apt/keyrings 0755
  if [[ ! -f /etc/apt/keyrings/nodesource.asc ]]; then
    run curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.asc
    run chmod a+r /etc/apt/keyrings/nodesource.asc
  fi

  write_file /etc/apt/sources.list.d/nodesource.list 0644 <<EOF
deb [signed-by=/etc/apt/keyrings/nodesource.asc] https://deb.nodesource.com/node_${NODE_MAJOR:-24}.x nodistro main
EOF

  refresh_apt
  install_pkgs nodejs
  if ((DRY_RUN)); then
    return 0
  fi
  log_ok "node $(node -v), npm $(npm -v)"
}
