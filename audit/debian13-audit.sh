#!/usr/bin/env bash
# debian13-audit.sh - read-only report of what postinstall was supposed to do.
# exits 0 when clean, 1 when something failed. warnings do not fail the run.
#
#   sudo bash audit/debian13-audit.sh
#   sudo bash audit/debian13-audit.sh --quiet
#   sudo bash audit/debian13-audit.sh --config config/postinstall.env

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
VERSION="0.1.0"

NEW_USER=ops
SSH_PORT=22
SUDO_NOPASSWD=0
DOTFILES_REPO=""
ENABLE_SHELL=1
ENABLE_PYTHON=1
ENABLE_NODE=0
ENABLE_GO=0
CONFIG_FILE=""
QUIET=0

while (($#)); do
  case $1 in
    --config) CONFIG_FILE=${2:-}; shift 2 ;;
    --config=*) CONFIG_FILE=${1#*=}; shift ;;
    --quiet) QUIET=1; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    --version) printf 'debian13-audit %s\n' "$VERSION"; exit 0 ;;
    -h | --help)
      cat <<EOF
debian13-audit $VERSION

usage: sudo bash ${0##*/} [options]

options:
  --config FILE   config file to source (default: config/postinstall.env)
  --quiet         only print warnings and failures
  --no-color      plain output for logs
  --version       print version
  -h, --help      this text

read-only. exits 0 when clean, 1 when a check failed.
EOF
      exit 0
      ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z $CONFIG_FILE ]] && [[ -r $ROOT_DIR/config/postinstall.env ]]; then
  CONFIG_FILE=$ROOT_DIR/config/postinstall.env
fi
if [[ -n $CONFIG_FILE ]]; then
  [[ -r $CONFIG_FILE ]] || { printf 'cannot read config: %s\n' "$CONFIG_FILE" >&2; exit 2; }
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

if [[ -t 1 ]] && [[ -z ${NO_COLOR:-} ]]; then
  R=$'\033[0m' B=$'\033[1m' D=$'\033[2m'
  RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' BLU=$'\033[34m'
else
  R='' B='' D='' RED='' GRN='' YEL='' BLU=''
fi

PASS=0 WARN=0 FAIL=0 SKIP=0

ok()   { PASS=$((PASS + 1)); ((QUIET)) || printf '  %sok  %s %s\n' "$GRN" "$R" "$*"; }
warn() { WARN=$((WARN + 1)); printf '  %swarn%s %s\n' "$YEL" "$R" "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  %sFAIL%s %s\n' "$RED" "$R" "$*"; }
skip() { SKIP=$((SKIP + 1)); ((QUIET)) || printf '  %sskip%s %s\n' "$D" "$R" "$*"; }
section() { ((QUIET)) || printf '\n%s== %s%s\n' "$B$BLU" "$*" "$R"; }
detail() { printf '       %s%s%s\n' "$D" "$*" "$R"; }

has() { command -v "$1" >/dev/null 2>&1; }
unit_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
unit_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }
is_root() { [[ ${EUID:-$(id -u)} -eq 0 ]]; }

# compare a sysctl key with the expected value
sysctl_is() {
  local key=$1 want=$2 got
  got=$(sysctl -n "$key" 2>/dev/null || printf '?')
  # sysctl prints tabs for some keys, values here are single tokens
  if [[ $got == "$want" ]]; then
    ok "sysctl $key = $want"
  else
    bad "sysctl $key = $got, wanted $want"
  fi
}

printf '%sdebian13-audit %s%s\n' "$B" "$VERSION" "$R"
printf 'host:   %s\n' "$(hostname)"
printf 'date:   %s\n' "$(date -Is)"
printf 'config: %s\n' "${CONFIG_FILE:-none, using defaults}"
printf 'user:   %s / ssh port: %s\n' "$NEW_USER" "$SSH_PORT"
is_root || printf '%snot root: nftables, sshd -T and some file checks will be skipped%s\n' "$YEL" "$R"

# ------------------------------- system -----------------------------

section "system"

if [[ -r /etc/os-release ]]; then
  os_id=$(. /etc/os-release; printf '%s' "${ID:-?}")
  os_ver=$(. /etc/os-release; printf '%s' "${VERSION_ID:-?}")
  os_name=$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-?}")
  if [[ $os_id == debian ]] && [[ $os_ver == 13 ]]; then
    ok "debian 13 ($os_name)"
  else
    warn "expected debian 13, found $os_id $os_ver"
  fi
else
  bad "/etc/os-release missing"
fi

if has systemctl && [[ "$(ps -p 1 -o comm= 2>/dev/null)" == systemd ]]; then
  ok "systemd is pid 1"
else
  bad "systemd is not pid 1"
fi

if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
  ok "clock synchronized"
else
  warn "clock not synchronized"
fi

if [[ -f /var/run/reboot-required ]]; then
  warn "reboot required: $(tr '\n' ' ' </var/run/reboot-required 2>/dev/null)"
else
  ok "no pending reboot"
fi

if [[ -d /sys/kernel/security/apparmor ]] || [[ -e /sys/module/apparmor/parameters/enabled ]]; then
  if [[ $(cat /sys/module/apparmor/parameters/enabled 2>/dev/null) == Y ]] || [[ -d /sys/kernel/security/apparmor ]]; then
    ok "apparmor enabled"
  else
    warn "apparmor present but not enabled"
  fi
else
  skip "apparmor not available"
fi

# -------------------------------- user ------------------------------

section "user and sudo"

if id -u "$NEW_USER" >/dev/null 2>&1; then
  ok "user $NEW_USER exists"
  if id -nG "$NEW_USER" | tr ' ' '\n' | grep -qx sudo; then
    ok "$NEW_USER in sudo group"
  else
    bad "$NEW_USER not in sudo group"
  fi
  if id -nG "$NEW_USER" | tr ' ' '\n' | grep -qx docker; then
    warn "$NEW_USER in docker group (root-equivalent, on purpose?)"
  fi

  keys=/home/$NEW_USER/.ssh/authorized_keys
  if [[ -s $keys ]]; then
    ok "authorized_keys has $(grep -c '^ssh-\|^ecdsa-\|^sk-' "$keys" 2>/dev/null || printf '?') key(s)"
    perms=$(stat -c '%a' "$keys")
    if [[ $perms == 600 ]]; then
      ok "authorized_keys mode 600"
    else
      bad "authorized_keys mode $perms, wanted 600"
    fi
    hperms=$(stat -c '%a' "/home/$NEW_USER/.ssh")
    if [[ $hperms == 700 ]]; then
      ok ".ssh mode 700"
    else
      warn ".ssh mode $hperms, wanted 700"
    fi
  else
    bad "no authorized_keys for $NEW_USER"
  fi

  if [[ ${ENABLE_SHELL:-1} == 1 ]]; then
    login_shell=$(getent passwd "$NEW_USER" | cut -d: -f7)
    if [[ $login_shell == */zsh ]]; then
      ok "login shell is zsh"
    else
      warn "login shell is ${login_shell:-unknown}, wanted zsh"
    fi
  fi
else
  bad "user $NEW_USER does not exist"
fi

if [[ $(passwd -S root 2>/dev/null | awk '{print $2}') == L ]]; then
  ok "root password locked"
else
  warn "root password not locked (PasswordAuthentication no still saves you)"
fi

sudoers=/etc/sudoers.d/90-postinstall-$NEW_USER
if [[ -f $sudoers ]]; then
  if [[ ${SUDO_NOPASSWD:-0} == 1 ]]; then
    ok "passwordless sudo configured as requested"
  else
    warn "$sudoers exists but SUDO_NOPASSWD=0"
  fi
fi

# -------------------------------- ssh -------------------------------

section "ssh"

if ! has sshd; then
  bad "openssh-server not installed"
else
  sshd_t=$(sshd -T 2>/dev/null)
  if [[ -z $sshd_t ]]; then
    warn "sshd -T failed, cannot read effective config"
  else
    check_sshd() {
      local key=$1 want=$2 got
      got=$(awk -v k="$key" '$1 == k { $1=""; sub(/^ /,""); print; exit }' <<<"$sshd_t")
      if [[ $got == "$want" ]]; then
        ok "sshd $key $want"
      else
        bad "sshd $key = '${got:-unset}', wanted '$want'"
      fi
    }
    check_sshd permitrootlogin no
    check_sshd pubkeyauthentication yes
    if [[ ${SSH_ALLOW_PASSWORD:-0} == 1 ]]; then
      check_sshd passwordauthentication yes
    else
      check_sshd passwordauthentication no
      check_sshd kbdinteractiveauthentication no
    fi
    check_sshd x11forwarding no
    check_sshd maxauthtries 3
    check_sshd port "$SSH_PORT"
  fi

  if [[ -f /etc/ssh/sshd_config.d/00-postinstall.conf ]]; then
    ok "drop-in /etc/ssh/sshd_config.d/00-postinstall.conf present"
  else
    warn "postinstall ssh drop-in missing, provider config is in charge"
  fi

  if ss -Hltn "sport = :$SSH_PORT" 2>/dev/null | grep -q .; then
    ok "something listens on tcp/$SSH_PORT"
  else
    bad "nothing listens on tcp/$SSH_PORT, you are reading this from somewhere else, right?"
  fi

  if unit_enabled ssh.socket; then
    detail "ssh.socket enabled (debian default), port lives in the socket unit"
  fi

  others=$(grep -lE '^\s*PasswordAuthentication\s+yes' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | grep -v 00-postinstall || true)
  [[ -n $others ]] && warn "password auth re-enabled in: $(tr '\n' ' ' <<<"$others")"
fi

# ------------------------------ firewall ----------------------------

section "firewall"

if ! has nft; then
  bad "nftables not installed"
else
  if unit_active nftables; then
    ok "nftables.service active"
  else
    bad "nftables.service not active"
  fi

  if ! is_root; then
    skip "ruleset checks need root"
  else
    rules=$(nft list ruleset 2>/dev/null)
    if grep -q 'table inet filter' <<<"$rules"; then
      ok "table inet filter present"
    else
      bad "table inet filter missing"
    fi

    input=$(nft list chain inet filter input 2>/dev/null)
    if grep -q 'policy drop' <<<"$input"; then
      ok "input policy drop"
    else
      bad "input policy is not drop"
    fi
    if grep -Eq "dport.*\b${SSH_PORT}\b" <<<"$input"; then
      ok "tcp/$SSH_PORT allowed in"
    else
      bad "tcp/$SSH_PORT not allowed, good luck"
    fi

    forward=$(nft list chain inet filter forward 2>/dev/null)
    if grep -q 'policy drop' <<<"$forward"; then
      ok "forward policy drop"
    else
      warn "forward policy is not drop"
    fi

    for p in ${EXTRA_TCP_PORTS//,/ }; do
      if grep -Eq "dport.*\b${p}\b" <<<"$input"; then
        ok "configured port $p allowed"
      else
        warn "configured port $p not in ruleset"
      fi
    done
  fi
fi

if unit_active ufw; then
  warn "ufw is active next to nftables, pick one"
else
  ok "ufw not in the way"
fi

# ------------------------------ fail2ban ----------------------------

section "fail2ban"

if ! has fail2ban-client; then
  bad "fail2ban not installed"
else
  if unit_active fail2ban; then
    ok "fail2ban.service active"
  else
    bad "fail2ban.service not active"
  fi
  if is_root; then
    jail=$(fail2ban-client status sshd 2>/dev/null || true)
    if grep -q 'Status for the jail: sshd' <<<"$jail"; then
      ok "sshd jail loaded"
      detail "$(grep -E 'Currently banned|Total banned' <<<"$jail" | tr -s ' ' | tr '\n' ' ')"
    else
      bad "sshd jail not loaded"
    fi
  else
    skip "jail status needs root"
  fi
fi

# ------------------------------- sysctl -----------------------------

section "sysctl"

hardening_conf=/etc/sysctl.d/99-postinstall-hardening.conf
if [[ -f $hardening_conf ]]; then
  ok "hardening drop-in present"
  while IFS='=' read -r key want; do
    key=$(xargs <<<"$key")
    want=$(xargs <<<"$want")
    [[ -z $key || $key == \#* ]] && continue
    sysctl_is "$key" "$want"
  done < <(grep -E '^[a-z]' "$hardening_conf")
else
  bad "no $hardening_conf, running on defaults"
fi

# ------------------------------ updates -----------------------------

section "updates"

if dpkg -s unattended-upgrades >/dev/null 2>&1; then
  ok "unattended-upgrades installed"
  if unit_active unattended-upgrades; then
    ok "unattended-upgrades service active"
  else
    warn "unattended-upgrades service inactive"
  fi
  if grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
    ok "apt periodic upgrades enabled"
  else
    bad "20auto-upgrades missing or disabled"
  fi
  if systemctl list-timers apt-daily-upgrade.timer --no-legend 2>/dev/null | grep -q apt-daily-upgrade; then
    ok "apt-daily-upgrade.timer armed"
  else
    warn "apt-daily-upgrade.timer not listed"
  fi
else
  bad "unattended-upgrades not installed"
fi

# ------------------------------ packages ----------------------------

section "packages"

missing=()
for p in git curl tmux zsh ripgrep fd-find bat jq htop btop rsync ncdu tree \
         gnupg ca-certificates unzip zip lsof dnsutils mtr-tiny fail2ban nftables; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if ((${#missing[@]} == 0)); then
  ok "base toolset installed"
else
  warn "missing: ${missing[*]}"
fi

# ------------------------------ runtimes ----------------------------

section "runtimes"

if [[ ${ENABLE_PYTHON:-1} == 1 ]]; then
  if has python3; then
    ok "python $(python3 --version 2>&1 | awk '{print $2}')"
  else
    bad "python3 missing"
  fi
  if dpkg -s python3-venv >/dev/null 2>&1; then
    ok "python3-venv installed"
  else
    bad "python3-venv missing, venvs will fail"
  fi
  if has pipx; then
    ok "pipx installed"
  else
    warn "pipx missing"
  fi
  has uv && detail "uv $(uv --version 2>/dev/null | awk '{print $2}')"
else
  skip "python module disabled"
fi

if [[ ${ENABLE_NODE:-0} == 1 ]]; then
  if has node; then
    ok "node $(node -v)"
  else
    bad "node missing but ENABLE_NODE=1"
  fi
else
  skip "node disabled"
fi

if [[ ${ENABLE_GO:-0} == 1 ]]; then
  if has go; then
    ok "go $(go version | awk '{print $3}')"
  else
    bad "go missing but ENABLE_GO=1"
  fi
else
  skip "go disabled"
fi

# ------------------------------- docker -----------------------------

section "docker"

if ! has docker; then
  skip "docker not installed"
else
  if unit_active docker; then ok "docker.service active"; else bad "docker.service not active"; fi
  if unit_enabled docker; then ok "docker.service enabled"; else warn "docker.service not enabled"; fi

  daemon=/etc/docker/daemon.json
  if [[ -r $daemon ]]; then
    if has jq && jq -e . "$daemon" >/dev/null 2>&1; then
      ok "daemon.json is valid json"
      if [[ $(jq -r '."no-new-privileges" // false' "$daemon") == true ]]; then
        ok "no-new-privileges on"
      else
        warn "no-new-privileges off"
      fi
      if [[ $(jq -r '."log-driver" // "none"' "$daemon") == json-file ]]; then
        ok "json-file log driver"
      else
        warn "unexpected log driver"
      fi
      if [[ $(jq -r '."live-restore" // false' "$daemon") == true ]]; then
        ok "live-restore on"
      else
        warn "live-restore off"
      fi
    else
      warn "daemon.json unreadable or not valid json"
    fi
  else
    warn "no /etc/docker/daemon.json, docker defaults apply"
  fi

  running=$(docker ps -q 2>/dev/null | wc -l)
  detail "$running container(s) running"
fi

# ----------------------------- cloudflare ---------------------------

section "cloudflare"

if has cloudflared; then
  ok "cloudflared $(cloudflared --version 2>/dev/null | awk '{print $3}')"
  if unit_active cloudflared; then
    ok "cloudflared.service active"
  else
    warn "cloudflared installed but tunnel service inactive"
  fi
else
  skip "cloudflared not installed"
fi

if has warp-cli; then
  status=$(warp-cli --accept-tos status 2>/dev/null | head -1)
  if grep -qi connected <<<"$status"; then
    ok "warp: $status"
  else
    warn "warp: ${status:-no status}"
  fi
else
  skip "warp-cli not installed"
fi

# ----------------------------- listeners ----------------------------

section "listeners"

if has ss; then
  listeners=$(ss -Hltn 2>/dev/null | awk '{print $4}' | grep -vE '^(127\.|\[::1\]|\[::ffff:127)' | sort -u)
  if [[ -z $listeners ]]; then
    ok "no world-facing tcp listeners"
  else
    count=$(wc -l <<<"$listeners")
    detail "world-facing: $(tr '\n' ' ' <<<"$listeners")"
    if grep -qE "[:.]$SSH_PORT\$" <<<"$listeners"; then
      ok "tcp/$SSH_PORT listening as expected"
    else
      bad "tcp/$SSH_PORT not in listener list"
    fi
    [[ $count -gt 1 ]] && warn "$count world-facing listeners, check what else is talking"
  fi
else
  skip "ss not available"
fi

# ------------------------------ dotfiles ----------------------------

if [[ -n ${DOTFILES_REPO:-} ]]; then
  section "dotfiles"
  df=${DOTFILES_DIR:-/home/$NEW_USER/.dotfiles}
  if [[ -d $df/.git ]]; then
    ok "dotfiles cloned at $df"
  else
    warn "DOTFILES_REPO set but nothing at $df"
  fi
fi

# ------------------------------- score ------------------------------

printf '\n%s== score%s\n' "$B$BLU" "$R"
printf '  %s%d ok%s  %s%d warn%s  %s%d fail%s  %d skip\n' \
  "$GRN" "$PASS" "$R" "$YEL" "$WARN" "$R" "$RED" "$FAIL" "$R" "$SKIP"

if ((FAIL > 0)); then
  printf '\n%s%d check(s) failed%s\n' "$RED" "$FAIL" "$R"
  exit 1
fi
printf '\n%sall good%s\n' "$GRN" "$R"
exit 0
