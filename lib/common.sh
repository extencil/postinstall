#!/usr/bin/env bash
# lib/common.sh - shared helpers for the postinstall entrypoint and its modules.
# sourced, never executed directly.

if [[ -n ${_POSTINSTALL_COMMON:-} ]]; then
  return 0
fi
_POSTINSTALL_COMMON=1

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT_DIR
export ROOT_DIR

LOG_DIR=${LOG_DIR:-/var/log/postinstall}
BACKUP_ROOT=${BACKUP_ROOT:-/var/backups/postinstall}
CHANGES=()
LAST_WRITE_CHANGED=0
export LAST_WRITE_CHANGED
APT_UPDATED=0
# unattended-upgrades can hold the dpkg lock for minutes; wait instead of dying.
APT_LOCK_TIMEOUT=${APT_LOCK_TIMEOUT:-300}

if [[ -t 1 ]] && [[ -z ${NO_COLOR:-} ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA=''
fi

log()       { printf '%s %s\n' "$(date +%H:%M:%S)" "$*"; }
log_step()  { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
log_info()  { printf '    %s\n' "$*"; }
log_ok()    { printf '    %s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_skip()  { printf '    %s[skip]%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
log_warn()  { printf '    %s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
log_err()   { printf '    %s[fail]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_dry()   { printf '    %s[dry-run]%s %s\n' "$C_MAGENTA" "$C_RESET" "$*"; }

die() {
  log_err "$*"
  exit 1
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "this needs root. try: sudo bash $0"
}

# run <cmd...>: the single gate every mutating command goes through.
run() {
  if ((DRY_RUN)); then
    log_dry "$*"
    return 0
  fi
  "$@"
}

run_as_user() {
  local user=$1
  shift
  run runuser -u "$user" -- "$@"
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'
}

apt_get() {
  run env DEBIAN_FRONTEND=noninteractive apt-get \
    -o "DPkg::Lock::Timeout=$APT_LOCK_TIMEOUT" \
    -o Acquire::Retries=3 "$@"
}

apt_update() {
  local force=${1:-} attempt
  if [[ $force != force ]] && ((APT_UPDATED)); then
    return 0
  fi
  log_info "apt-get update"
  for attempt in 1 2 3; do
    if apt_get update -qq; then
      APT_UPDATED=1
      return 0
    fi
    if ((attempt < 3)); then
      log_warn "apt update failed, retrying in 5s (attempt $attempt/3)"
      sleep 5
    fi
  done
  die "apt-get update failed after 3 attempts"
}

# install_pkgs name [name...]: skips packages already installed.
install_pkgs() {
  local missing=() p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if ((${#missing[@]} == 0)); then
    log_skip "already installed: $*"
    return 0
  fi
  log_info "installing: ${missing[*]}"
  apt_get install -y -qq --no-install-recommends "${missing[@]}"
}

ensure_dir() {
  local path=$1 mode=${2:-0755}
  [[ -d $path ]] && return 0
  run install -d -m "$mode" "$path"
}

backup_file() {
  local file=$1 dest
  [[ -e $file ]] || return 0
  ((DRY_RUN)) && return 0
  dest="$BACKUP_ROOT/$(date +%Y%m%dT%H%M%S)"
  install -d -m 0700 "$dest"
  cp -a --parents "$file" "$dest/" 2>/dev/null || cp -a "$file" "$dest/$(basename "$file")"
}

# write_file <path> [mode]  (content on stdin)
# idempotent: leaves the file alone when content already matches.
# sets LAST_WRITE_CHANGED=1 when the file changed.
write_file() {
  local path=$1 mode=${2:-0644} content tmp
  content=$(cat)
  LAST_WRITE_CHANGED=0
  if [[ -f $path ]] && [[ "$(cat "$path")" == "$content" ]]; then
    log_skip "$path"
    return 0
  fi
  if ((DRY_RUN)); then
    log_dry "write $path"
    LAST_WRITE_CHANGED=1
    CHANGES+=("$path")
    return 0
  fi
  ensure_dir "$(dirname "$path")"
  backup_file "$path"
  tmp=$(mktemp)
  printf '%s\n' "$content" >"$tmp"
  install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
  LAST_WRITE_CHANGED=1
  CHANGES+=("$path")
  log_ok "wrote $path"
}

service_active()  { systemctl is-active --quiet "$1" 2>/dev/null; }
service_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

# restart_if_changed <unit> <changed-flag>
restart_if_changed() {
  local unit=$1 changed=$2
  [[ $changed == 1 ]] || return 0
  run systemctl restart "$unit"
}

enable_now() {
  run systemctl enable --now "$1"
}

refresh_apt() {
  APT_UPDATED=0
  apt_update force
}

# distro facts, read in a subshell so the caller's namespace stays clean.
debian_codename() {
  ( . /etc/os-release 2>/dev/null && printf '%s' "${VERSION_CODENAME:-unknown}" )
}

debian_version_id() {
  ( . /etc/os-release 2>/dev/null && printf '%s' "${VERSION_ID:-0}" )
}

# Port numbers are interpolated into nftables, sshd and systemd config.
validate_ssh_port() {
  if [[ ! ${SSH_PORT:-} =~ ^[1-9][0-9]{0,4}$ ]] || ((SSH_PORT > 65535)); then
    die "SSH_PORT must be an integer between 1 and 65535, without leading zeros"
  fi
}

# NEW_USER lands in adduser, sudoers and AllowUsers before anyone logs in.
validate_new_user() {
  [[ ${NEW_USER:-} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ||
    die "NEW_USER must be a lowercase unix account name, got '${NEW_USER:-}'"
  [[ $NEW_USER != root ]] || die "NEW_USER=root defeats the point of a separate account"
  local -a disabled=()
  local u disabled_list=${DISABLE_DEFAULT_USERS:-}
  read -r -a disabled <<<"${disabled_list//,/ }"
  for u in "${disabled[@]}"; do
    [[ $u != "$NEW_USER" ]] || die "NEW_USER=$NEW_USER is also listed in DISABLE_DEFAULT_USERS"
  done
}

# Fail before users disables the old account if the ssh allowlist has no path
# back in for NEW_USER.
validate_ssh_users() {
  local -a allow=()
  local u entry allow_list=${SSH_ALLOW_USERS:-}
  read -r -a allow <<<"${allow_list//,/ }"
  if ((${#allow[@]} == 0)); then
    return 0
  fi
  for entry in "${allow[@]}"; do
    [[ $entry == "$NEW_USER" || $entry == "$NEW_USER"@* ]] && return 0
  done
  die "SSH_ALLOW_USERS does not permit $NEW_USER"
}
