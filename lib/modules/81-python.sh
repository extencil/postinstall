#!/usr/bin/env bash
# module: python - interpreter, venvs, pipx, uv. no global pip nonsense.

module_python() {
  log_step "python"

  install_pkgs python3 python3-dev python3-venv python3-pip pipx

  if [[ ${PYTHON_INSTALL_UV:-1} == 1 ]]; then
    if command -v uv >/dev/null 2>&1; then
      log_skip "uv $(uv --version 2>/dev/null | awk '{print $2}')"
    else
      log_info "installing uv into /usr/local/bin"
      if ((DRY_RUN)); then
        log_dry "curl -LsSf https://astral.sh/uv/install.sh | sh (UV_INSTALL_DIR=/usr/local/bin)"
      else
        curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
        log_ok "uv $(uv --version 2>/dev/null | awk '{print $2}')"
      fi
    fi
  fi

  if run_as_user "$NEW_USER" pipx ensurepath >/dev/null 2>&1; then
    log_ok "pipx path wired for $NEW_USER"
  else
    log_warn "pipx ensurepath failed, harmless if pipx is new"
  fi
}
