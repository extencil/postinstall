#!/usr/bin/env bash
# module: go - distro toolchain. boring on purpose, upgrade when you care.

module_go() {
  log_step "go"

  if command -v go >/dev/null 2>&1; then
    log_skip "go $(go version | awk '{print $3}')"
    return 0
  fi

  install_pkgs golang-go
  if ((DRY_RUN)); then
    return 0
  fi
  log_ok "go $(go version | awk '{print $3}')"
}
