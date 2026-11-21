#!/usr/bin/env bash
# module: docker - upstream repo, one sane daemon.json, log rotation on.

module_docker() {
  log_step "docker"

  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    ensure_dir /etc/apt/keyrings 0755
    run curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    run chmod a+r /etc/apt/keyrings/docker.asc
    log_ok "docker repo key installed"
  else
    log_skip "docker repo key present"
  fi

  write_file /etc/apt/sources.list.d/docker.list 0644 <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $DEBIAN_CODENAME stable
EOF

  refresh_apt
  install_pkgs docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  write_file /etc/docker/daemon.json 0644 <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "no-new-privileges": true,
  "userland-proxy": false
}
EOF

  if [[ $LAST_WRITE_CHANGED == 1 ]] || ! service_active docker; then
    enable_now docker
    run systemctl restart docker
    log_ok "docker restarted with daemon.json"
  else
    log_skip "docker already happy"
  fi

  if [[ ${DOCKER_ADD_USER_TO_GROUP:-1} == 1 ]]; then
    if ! id -u "$NEW_USER" >/dev/null 2>&1; then
      log_warn "user $NEW_USER does not exist, skipping docker group"
    elif id -nG "$NEW_USER" | tr ' ' '\n' | grep -qx docker; then
      log_skip "$NEW_USER already in docker group"
    else
      run usermod -aG docker "$NEW_USER"
      log_ok "$NEW_USER -> docker group (remember: that is root, basically)"
    fi
  fi
}
