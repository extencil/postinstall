#!/usr/bin/env bash
# module: verify - run the audit and show the scoreboard. never aborts.

module_verify() {
  log_step "verify"

  local audit=$ROOT_DIR/audit/debian13-audit.sh
  if [[ ! -x $audit ]]; then
    log_warn "audit script missing: $audit"
    return 0
  fi

  ((DRY_RUN)) && { log_dry "bash $audit"; return 0; }

  local args=()
  [[ -n ${CONFIG_FILE:-} ]] && args+=(--config "$CONFIG_FILE")
  if bash "$audit" "${args[@]}"; then
    log_ok "audit clean"
  else
    log_warn "audit found problems, run: bash $audit"
  fi
}
