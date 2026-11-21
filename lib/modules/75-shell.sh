#!/usr/bin/env bash
# module: shell - zsh as the login shell for the human. dotfiles do the rest.

module_shell() {
  log_step "shell"

  install_pkgs zsh

  local zsh_path
  zsh_path=$(command -v zsh)
  local current
  current=$(getent passwd "$NEW_USER" | cut -d: -f7)

  if [[ $current == "$zsh_path" ]]; then
    log_skip "$NEW_USER already uses zsh"
  else
    run chsh -s "$zsh_path" "$NEW_USER"
    log_ok "$NEW_USER shell -> $zsh_path"
  fi

  if [[ ! -f /home/$NEW_USER/.zshrc ]]; then
    log_info "no .zshrc yet, the dotfiles module is the place for it"
  fi
}
