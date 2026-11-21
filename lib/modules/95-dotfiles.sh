#!/usr/bin/env bash
# module: dotfiles - clone the repo that makes the box feel like mine.

module_dotfiles() {
  log_step "dotfiles"

  install_pkgs age gnupg

  if [[ -z ${DOTFILES_REPO:-} ]]; then
    log_skip "DOTFILES_REPO is empty, nothing to clone"
    return 0
  fi

  local dir=${DOTFILES_DIR:-/home/$NEW_USER/.dotfiles}

  if [[ -d $dir/.git ]]; then
    if [[ ${DOTFILES_UPDATE:-1} == 1 ]]; then
      run_as_user "$NEW_USER" git -C "$dir" pull --ff-only -q
      log_ok "dotfiles updated in $dir"
    else
      log_skip "$dir already cloned"
    fi
  elif [[ -d $dir ]]; then
    log_warn "$dir exists but is not a git repo, leaving it alone"
    return 0
  else
    run_as_user "$NEW_USER" git clone -q "$DOTFILES_REPO" "$dir"
    log_ok "cloned $DOTFILES_REPO -> $dir"
  fi

  if [[ -n ${DOTFILES_INSTALL_CMD:-} ]]; then
    log_info "running: $DOTFILES_INSTALL_CMD"
    run_as_user "$NEW_USER" env HOME=/home/"$NEW_USER" sh -c "cd '$dir' && $DOTFILES_INSTALL_CMD"
    log_ok "dotfiles install command finished"
  else
    log_info "no DOTFILES_INSTALL_CMD set, symlink by hand or add one"
  fi
}
