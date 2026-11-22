#!/usr/bin/env bash
# debian13-postinstall.sh - one pass over a fresh debian 13 vps.
#
#   sudo bash debian13-postinstall.sh --config config/postinstall.env
#   sudo bash debian13-postinstall.sh --dry-run
#   sudo bash debian13-postinstall.sh --only ssh,firewall
#
# idempotent: run it again after adding a module to the config, it skips
# what is already done. anything it overwrites is backed up first.

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

VERSION="0.1.0"

# ----------------------------- defaults -----------------------------

: "${NEW_USER:=ops}"
: "${NEW_USER_PASSWORD:=}"
: "${NEW_USER_PASSWORD_FILE:=}"
: "${DISABLE_DEFAULT_USERS:=debian}"
: "${SSH_PORT:=1}"
: "${HOSTNAME_SET:=}"
: "${TIMEZONE:=UTC}"
: "${SSH_PUBKEY_FILE:=}"
: "${SSH_PUBKEY:=}"
: "${SSH_ALLOW_USERS:=}"
: "${SSH_ALLOW_PASSWORD:=0}"
: "${SSH_ALLOW_TCP_FORWARDING:=1}"
: "${SSH_PRANK_BANNER_FILE:=}"
: "${EXTRA_TCP_PORTS:=}"
: "${EXTRA_UDP_PORTS:=}"
: "${SUDO_NOPASSWD:=0}"

: "${ENABLE_USERS:=1}"
: "${ENABLE_FIREWALL:=1}"
: "${ENABLE_SSH:=1}"
: "${ENABLE_SSH_PRANK:=1}"
: "${ENABLE_FAIL2BAN:=1}"
: "${ENABLE_SYSCTL:=1}"
: "${ENABLE_UPDATES:=1}"
: "${ENABLE_TOOLS:=1}"
: "${ENABLE_SHELL:=1}"
: "${ENABLE_DOCKER:=1}"
: "${ENABLE_PYTHON:=1}"
: "${ENABLE_NODE:=0}"
: "${ENABLE_GO:=0}"
: "${ENABLE_CLOUDFLARED:=0}"
: "${ENABLE_DOTFILES:=0}"
: "${ENABLE_VERIFY:=1}"

: "${DOCKER_ADD_USER_TO_GROUP:=1}"
: "${PYTHON_INSTALL_UV:=1}"
: "${NODE_MAJOR:=24}"
: "${CLOUDFLARED_TOKEN_FILE:=}"
: "${CLOUDFLARED_TOKEN:=}"
: "${DOTFILES_REPO:=}"
: "${DOTFILES_DIR:=}"
: "${DOTFILES_INSTALL_CMD:=}"
: "${DOTFILES_UPDATE:=1}"

DRY_RUN=0
ONLY=""
SKIP=""
CONFIG_FILE=""
DEBIAN_CODENAME=$(debian_codename)

MODULES=(preflight users firewall ssh ssh_prank fail2ban sysctl updates tools shell
         docker python node go cloudflared dotfiles verify)

# ------------------------------ usage -------------------------------

usage() {
  cat <<EOF
debian13-postinstall $VERSION

usage: sudo bash ${0##*/} [options]

options:
  --config FILE     config file to source (default: config/postinstall.env)
  --only LIST       run only these modules, comma separated (preflight still runs)
  --skip LIST       skip these modules, comma separated
  --dry-run         print what would change, touch nothing
  --yes             accepted for muscle memory, nothing prompts anyway
  --list            show modules and whether they are enabled, then exit
  --audit           run the audit only, then exit
  --user NAME       override NEW_USER
  --port N          override SSH_PORT
  --timezone TZ     override TIMEZONE
  --version         print version
  -h, --help        this text

modules:
  ${MODULES[*]}

examples:
  sudo bash ${0##*/} --dry-run
  sudo bash ${0##*/} --only firewall,ssh,ssh_prank,fail2ban
  sudo bash ${0##*/} --skip docker,node,go --config ~/vps.env

config precedence: flags > config file > environment > defaults.
EOF
}

# --------------------------- config load ----------------------------

# first pass: where is the config? it has to load before flags can override it.
_argv=("$@")
for ((i = 0; i < ${#_argv[@]}; i++)); do
  case ${_argv[i]} in
    --config)
      CONFIG_FILE=${_argv[i + 1]:-}
      i=$((i + 1))
      ;;
    --config=*) CONFIG_FILE=${_argv[i]#*=} ;;
  esac
done

if [[ -z $CONFIG_FILE ]]; then
  if [[ -n ${POSTINSTALL_CONFIG:-} ]]; then
    CONFIG_FILE=$POSTINSTALL_CONFIG
  elif [[ -f $SCRIPT_DIR/config/postinstall.env ]]; then
    CONFIG_FILE=$SCRIPT_DIR/config/postinstall.env
  fi
fi

if [[ -n $CONFIG_FILE ]]; then
  [[ -r $CONFIG_FILE ]] || die "cannot read config file: $CONFIG_FILE"
  log_info "config: $CONFIG_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
  # Do not leak a bootstrap password into apt, curl or any other child.
  if [[ -n ${NEW_USER_PASSWORD:-} ]]; then
    export -n NEW_USER_PASSWORD
  fi
  # Same for the inline tunnel token fallback. Prefer the 0600 file.
  if [[ -n ${CLOUDFLARED_TOKEN:-} ]]; then
    export -n CLOUDFLARED_TOKEN
  fi
fi

# --------------------------- flag parsing ---------------------------

while (($#)); do
  case $1 in
    --config)
      shift
      CONFIG_FILE=${1:-}
      shift
      ;;
    --config=*)
      CONFIG_FILE=${1#*=}
      shift
      ;;
    --only)
      ONLY=${2:-}
      shift 2
      ;;
    --skip)
      SKIP=${2:-}
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --yes)
      shift
      ;;
    --list) LIST=1; shift ;;
    --audit) AUDIT_ONLY=1; shift ;;
    --user) NEW_USER=${2:-}; shift 2 ;;
    --port) SSH_PORT=${2:-}; shift 2 ;;
    --timezone) TIMEZONE=${2:-}; shift 2 ;;
    --version)
      printf 'debian13-postinstall %s\n' "$VERSION"
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown flag: $1 (try --help)"
      ;;
  esac
done

module_var() {
  local id=$1
  printf 'ENABLE_%s' "${id^^}"
}

module_enabled() {
  local id=$1 var
  [[ $id == preflight ]] && [[ ",$SKIP," != *",$id,"* ]] && return 0
  var=$(module_var "$id")
  if [[ -n $ONLY ]]; then
    [[ ",$ONLY," == *",$id,"* ]]
    return
  fi
  [[ ",$SKIP," == *",$id,"* ]] && return 1
  [[ ${!var:-0} == 1 ]]
}

if [[ -n $ONLY || -n $SKIP ]]; then
  for id in ${ONLY//,/ } ${SKIP//,/ }; do
    [[ " ${MODULES[*]} " == *" $id "* ]] || die "unknown module: $id"
  done
fi

if [[ ${LIST:-0} == 1 ]]; then
  printf '%-12s %s\n' "module" "enabled"
  for id in "${MODULES[@]}"; do
    if module_enabled "$id"; then
      printf '%-12s yes\n' "$id"
    else
      printf '%-12s no\n' "$id"
    fi
  done
  if [[ -n $CONFIG_FILE ]]; then
    printf '\nconfig: %s\n' "$CONFIG_FILE"
  else
    printf '\nconfig: none, using defaults\n'
  fi
  exit 0
fi

require_root

if [[ ${AUDIT_ONLY:-0} == 1 ]]; then
  args=()
  [[ -n $CONFIG_FILE ]] && args+=(--config "$CONFIG_FILE")
  exec bash "$SCRIPT_DIR/audit/debian13-audit.sh" "${args[@]}"
fi

# Reject invalid port input before preflight or the firewall changes anything.
validate_ssh_port
validate_new_user
validate_ssh_users
if [[ $SSH_PORT == 22 ]] && { module_enabled ssh_prank || service_active postinstall-ssh-prank; }; then
  die "SSH_PORT=22 conflicts with ssh_prank. choose another real ssh port or stop and disable the decoy"
fi

# ------------------------------ logging -----------------------------

if ((DRY_RUN)); then
  RUN_ID="dry-run-$(date +%Y%m%dT%H%M%S)"
  LOG_FILE="${LOG_DIR}/${RUN_ID}.log"
else
  ensure_dir "$LOG_DIR" 0750
  LOG_FILE="$LOG_DIR/$(date +%Y%m%dT%H%M%S).log"
fi

if ((DRY_RUN)); then
  :
else
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

rc=0
trap 'rc=$?; log_err "failed at ${BASH_SOURCE[0]}:${LINENO}: $BASH_COMMAND (exit $rc)"; exit "$rc"' ERR

printf '\n%sdebian13-postinstall %s%s\n' "$C_BOLD" "$VERSION" "$C_RESET"
log_info "host: $(hostname) / debian $DEBIAN_CODENAME / $(dpkg --print-architecture)"
log_info "user: $NEW_USER / ssh port: $SSH_PORT"
log_info "mode: $( ((DRY_RUN)) && printf 'dry-run' || printf 'apply' )"
[[ -n $ONLY ]] && log_info "only: $ONLY"
[[ -n $SKIP ]] && log_info "skip: $SKIP"
((DRY_RUN)) || log_info "log: $LOG_FILE"

# ------------------------------ modules -----------------------------

for id in "${MODULES[@]}"; do
  module_enabled "$id" || continue
  case $id in
    preflight) mod_file="$SCRIPT_DIR/lib/modules/00-preflight.sh" ;;
    users) mod_file="$SCRIPT_DIR/lib/modules/10-users.sh" ;;
    firewall) mod_file="$SCRIPT_DIR/lib/modules/20-firewall.sh" ;;
    ssh) mod_file="$SCRIPT_DIR/lib/modules/30-ssh.sh" ;;
    ssh_prank) mod_file="$SCRIPT_DIR/lib/modules/35-ssh-prank.sh" ;;
    fail2ban) mod_file="$SCRIPT_DIR/lib/modules/40-fail2ban.sh" ;;
    sysctl) mod_file="$SCRIPT_DIR/lib/modules/50-sysctl.sh" ;;
    updates) mod_file="$SCRIPT_DIR/lib/modules/60-updates.sh" ;;
    tools) mod_file="$SCRIPT_DIR/lib/modules/70-tools.sh" ;;
    shell) mod_file="$SCRIPT_DIR/lib/modules/75-shell.sh" ;;
    docker) mod_file="$SCRIPT_DIR/lib/modules/80-docker.sh" ;;
    python) mod_file="$SCRIPT_DIR/lib/modules/81-python.sh" ;;
    node) mod_file="$SCRIPT_DIR/lib/modules/82-node.sh" ;;
    go) mod_file="$SCRIPT_DIR/lib/modules/83-go.sh" ;;
    cloudflared) mod_file="$SCRIPT_DIR/lib/modules/90-cloudflared.sh" ;;
    dotfiles) mod_file="$SCRIPT_DIR/lib/modules/95-dotfiles.sh" ;;
    verify) mod_file="$SCRIPT_DIR/lib/modules/99-verify.sh" ;;
  esac
  # shellcheck disable=SC1090
  source "$mod_file"
  "module_$id"
done

# ------------------------------ summary -----------------------------

printf '\n'
if ((${#CHANGES[@]})); then
  log_info "${#CHANGES[@]} file(s) changed:"
  printf '    %s\n' "${CHANGES[@]}"
else
  log_info "nothing changed, box already matched the config"
fi

printf '\n%snext%s\n' "$C_BOLD" "$C_RESET"
log_info "audit:   sudo bash $SCRIPT_DIR/audit/debian13-audit.sh"
log_info "re-run:  sudo bash $SCRIPT_DIR/debian13-postinstall.sh"
if [[ $SSH_PORT != 22 ]]; then
  log_info "test:    ssh -p $SSH_PORT $NEW_USER@<host>   # keep this shell open"
fi
if module_enabled users && [[ -z ${NEW_USER_PASSWORD:-} ]]; then
  pwfile=${NEW_USER_PASSWORD_FILE:-/root/postinstall-$NEW_USER.password}
  [[ $pwfile == /* ]] || pwfile=$SCRIPT_DIR/$pwfile
  log_info "password: $pwfile (0400/0600)"
fi
log_info "backups: $BACKUP_ROOT"
printf '\n'
