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
NEW_USER_PASSWORD=""
NEW_USER_PASSWORD_FILE=""
DISABLE_DEFAULT_USERS=debian
LOCK_ROOT_PASSWORD=1
SSH_PORT=1
ENABLE_CLOUDFLARED=0
ENABLE_SSH_PRANK=1
EXTRA_TCP_PORTS=""
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

user_home() { getent passwd "$1" 2>/dev/null | cut -d: -f6; }
user_shell() { getent passwd "$1" 2>/dev/null | cut -d: -f7; }
password_state() { passwd -S "$1" 2>/dev/null | awk '{print $2}'; }
in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
valid_key_file() {
  grep -Eq '(^|[[:space:]])(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[^[:space:]]+|sk-ssh-[^[:space:]]+)[[:space:]]+AAAA' "$1" 2>/dev/null
}

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
  if in_group "$NEW_USER" sudo; then
    ok "$NEW_USER in sudo group"
  else
    bad "$NEW_USER not in sudo group"
  fi
  if in_group "$NEW_USER" docker; then
    warn "$NEW_USER in docker group (root-equivalent, on purpose?)"
  fi

  home=$(user_home "$NEW_USER")
  keys=$home/.ssh/authorized_keys
  if [[ -s $keys ]] && valid_key_file "$keys"; then
    ok "authorized_keys has a usable public key"
    perms=$(stat -c '%a' "$keys")
    if [[ $perms == 600 ]]; then
      ok "authorized_keys mode 600"
    else
      bad "authorized_keys mode $perms, wanted 600"
    fi
    owner=$(stat -c '%U' "$keys")
    if [[ $owner == "$NEW_USER" ]]; then
      ok "authorized_keys owned by $NEW_USER"
    else
      bad "authorized_keys owned by $owner, wanted $NEW_USER"
    fi
    hperms=$(stat -c '%a' "$home/.ssh")
    if [[ $hperms == 700 ]]; then
      ok ".ssh mode 700"
    else
      bad ".ssh mode $hperms, wanted 700"
    fi
    howner=$(stat -c '%U' "$home/.ssh")
    if [[ $howner == "$NEW_USER" ]]; then
      ok ".ssh owned by $NEW_USER"
    else
      bad ".ssh owned by $howner, wanted $NEW_USER"
    fi
  elif [[ -s $keys ]]; then
    bad "authorized_keys has no usable public key"
  else
    bad "no authorized_keys for $NEW_USER"
  fi

  if is_root; then
    pstate=$(password_state "$NEW_USER")
    if [[ $pstate == P ]]; then
      ok "$NEW_USER has a usable password"
    elif [[ ${SUDO_NOPASSWD:-0} == 1 ]]; then
      warn "$NEW_USER password is not set; key login plus passwordless sudo still works"
    else
      bad "$NEW_USER has no usable password and SUDO_NOPASSWD=0, sudo and console login fail"
    fi
    pwfile=${NEW_USER_PASSWORD_FILE:-/root/postinstall-$NEW_USER.password}
    [[ $pwfile == /* ]] || pwfile=$ROOT_DIR/$pwfile
    if [[ -n ${NEW_USER_PASSWORD:-} ]]; then
      skip "password supplied in config, no generated file expected"
    elif [[ -f $pwfile ]]; then
      pwperms=$(stat -c '%a' "$pwfile")
      if [[ $pwperms == 400 || $pwperms == 600 ]]; then
        ok "password file mode $pwperms"
      else
        bad "password file mode $pwperms, wanted 0400 or 0600"
      fi
      pwowner=$(stat -c '%U:%G' "$pwfile")
      if [[ $pwowner == root:root || $pwowner == "$NEW_USER:$NEW_USER" ]]; then
        ok "password file owned by $pwowner"
      else
        bad "password file owned by $pwowner, wanted root or $NEW_USER"
      fi
    elif [[ ${SUDO_NOPASSWD:-0} == 1 ]]; then
      warn "no password file at $pwfile (passwordless sudo still works)"
    else
      warn "no password file at $pwfile; password may have been rotated manually"
    fi
  else
    skip "password state needs root"
  fi

  if [[ ${ENABLE_SHELL:-1} == 1 ]]; then
    login_shell=$(user_shell "$NEW_USER")
    if [[ $login_shell == */zsh ]]; then
      ok "login shell is zsh"
    else
      warn "login shell is ${login_shell:-unknown}, wanted zsh"
    fi
  fi
else
  bad "user $NEW_USER does not exist"
fi

if [[ ${LOCK_ROOT_PASSWORD:-1} != 1 ]]; then
  warn "root password left unlocked (LOCK_ROOT_PASSWORD=0)"
elif [[ $(passwd -S root 2>/dev/null | awk '{print $2}') == L ]]; then
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

# --------------------------- disabled accounts ----------------------

section "disabled accounts"

disabled=()
read -r -a disabled <<<"${DISABLE_DEFAULT_USERS//,/ }"
if ((${#disabled[@]} == 0)); then
  skip "no default accounts configured for disabling"
else
  for u in "${disabled[@]}"; do
    if [[ $u == root ]]; then
      bad "DISABLE_DEFAULT_USERS contains root"
      continue
    fi
    if [[ $u == "$NEW_USER" ]]; then
      bad "DISABLE_DEFAULT_USERS contains NEW_USER=$NEW_USER"
      continue
    fi
    if ! id -u "$u" >/dev/null 2>&1; then
      skip "default account $u not present"
      continue
    fi

    shell=$(user_shell "$u")
    if [[ $shell == */nologin || $shell == */false ]]; then
      ok "$u shell is $shell"
    else
      bad "$u shell is ${shell:-unknown}, wanted nologin"
    fi
    for g in sudo docker; do
      if in_group "$u" "$g"; then
        bad "$u still in $g group"
      else
        ok "$u not in $g group"
      fi
    done

    if is_root; then
      state=$(password_state "$u")
      if [[ $state == L ]]; then
        ok "$u password locked"
      else
        bad "$u password state is ${state:-unknown}, wanted L"
      fi
      expire=$(awk -F: -v name="$u" '$1 == name { print $8 }' /etc/shadow 2>/dev/null || true)
      if [[ -n $expire && $expire != 0 ]]; then
        ok "$u account expired"
      else
        bad "$u account does not expire"
      fi
      grants=$(grep -lE "^[[:space:]]*${u}[[:space:]]" /etc/sudoers /etc/sudoers.d/* 2>/dev/null || true)
      if [[ -z $grants ]]; then
        ok "$u has no sudoers grant"
      else
        bad "$u still has a sudoers grant: $(tr '\n' ' ' <<<"$grants")"
      fi
    else
      skip "$u password, expiry and sudoers checks need root"
    fi
  done
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
      check_sshd authenticationmethods publickey
    fi
    check_sshd x11forwarding no
    check_sshd maxauthtries 3

    allow_got=$(awk '$1 == "allowusers" { $1=""; sub(/^ /,""); print; exit }' <<<"$sshd_t")
    allow_want=""
    read -r -a wanted <<<"${SSH_ALLOW_USERS//,/ }"
    for u in "${wanted[@]}"; do
      [[ " ${disabled[*]} " == *" $u "* ]] && continue
      allow_want+="$u "
    done
    allow_want=${allow_want% }
    [[ -n $allow_want ]] || allow_want=$NEW_USER
    if [[ $allow_got == "$allow_want" ]]; then
      ok "sshd allowusers $allow_want"
    else
      bad "sshd allowusers = '${allow_got:-unset}', wanted '$allow_want'"
    fi
    if [[ " $allow_got " != *" $NEW_USER "* && " $allow_got " != *" $NEW_USER@"* ]]; then
      bad "sshd allowusers does not contain $NEW_USER"
    fi
    deny_got=$(awk '$1 == "denyusers" { $1=""; sub(/^ /,""); print; exit }' <<<"$sshd_t")
    missing_deny=0
    for u in "${disabled[@]}"; do
      [[ $u == root || $u == "$NEW_USER" ]] && continue
      if [[ " $allow_got " == *" $u "* ]]; then
        bad "disabled account $u still in sshd allowusers"
      fi
      if [[ " $deny_got " != *" $u "* ]]; then
        bad "disabled account $u missing from sshd denyusers"
        missing_deny=1
      fi
    done
    if ((${#disabled[@]})) && ((missing_deny == 0)); then
      ok "disabled accounts blocked by sshd denyusers"
    fi
    ports=$(awk '$1 == "port" {print $2}' <<<"$sshd_t")
    if [[ $ports == "$SSH_PORT" ]]; then
      ok "sshd port $SSH_PORT only"
    else
      bad "sshd ports differ from SSH_PORT=$SSH_PORT"
      detail "check all Port directives, including provider drop-ins"
    fi
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

# ------------------------------ ssh prank ---------------------------

section "ssh prank"

prank_unit=/etc/systemd/system/postinstall-ssh-prank.service
if [[ ${ENABLE_SSH_PRANK:-1} != 1 ]]; then
  skip "ssh prank disabled in config"
  if unit_active postinstall-ssh-prank; then
    warn "ssh prank still running; disabling a module does not stop its service"
  fi
elif [[ ! -f $prank_unit ]]; then
  bad "ssh prank enabled but service is not installed"
else
  for path in "$prank_unit" /usr/local/lib/postinstall/ssh-prank.py /etc/postinstall/ssh-prank-banner.txt; do
    if [[ -f $path ]] && [[ $(stat -c '%u:%g:%a' "$path" 2>/dev/null) == 0:0:644 ]]; then
      ok "$path owned by root, mode 644"
    else
      bad "$path missing or has unexpected ownership or mode"
    fi
  done
  if [[ $SSH_PORT == 22 ]]; then
    bad "real ssh and the decoy are configured for the same port"
  fi
  if unit_active postinstall-ssh-prank; then
    ok "ssh prank service active"
  else
    bad "ssh prank service inactive"
  fi
  if unit_enabled postinstall-ssh-prank; then
    ok "ssh prank service enabled"
  else
    bad "ssh prank service not enabled"
  fi
  if ! has ss; then
    skip "ssh prank listener check needs ss"
  elif ! is_root; then
    skip "ssh prank listener ownership check needs root"
  else
    prank_pid=$(systemctl show -p MainPID --value postinstall-ssh-prank 2>/dev/null)
    prank_listener=$(ss -Hltnp 'sport = :22' 2>/dev/null)
    if [[ $prank_pid =~ ^[1-9][0-9]*$ ]] &&
       [[ -n $prank_listener ]] &&
       ! grep -v "pid=$prank_pid," <<<"$prank_listener" | grep -q .; then
      ok "all tcp/22 listeners belong to the ssh prank service"
    else
      bad "tcp/22 listener does not belong exclusively to the ssh prank service"
    fi
    key=/var/lib/private/postinstall-ssh-prank/host_key
    if [[ -f $key ]] && [[ $(stat -c '%a' "$key") == 600 ]]; then
      ok "ssh prank private host key mode 600"
    else
      bad "ssh prank private host key missing or not mode 600"
    fi
  fi
  for setting in 'DynamicUser=yes' 'NoNewPrivileges=yes' 'ProtectSystem=strict' 'Type=notify'; do
    if [[ $(systemctl show -p "${setting%%=*}" --value postinstall-ssh-prank 2>/dev/null) == "${setting#*=}" ]]; then
      ok "ssh prank $setting"
    else
      bad "ssh prank effective $setting missing"
    fi
  done
  if [[ -r /etc/postinstall/ssh-prank-banner.txt ]] && [[ -s /etc/postinstall/ssh-prank-banner.txt ]]; then
    ok "ssh prank banner present"
  else
    bad "ssh prank banner missing or unreadable"
  fi
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

    if [[ ${ENABLE_SSH_PRANK:-1} == 1 ]] || unit_active postinstall-ssh-prank; then
      if grep -Eq 'tcp dport.*\b22\b.*accept' <<<"$input"; then
        ok "tcp/22 decoy allowed in"
      else
        bad "tcp/22 decoy not allowed in"
      fi
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

if [[ ${ENABLE_CLOUDFLARED:-0} != 1 ]]; then
  skip "cloudflared disabled in config"
  if has cloudflared && unit_active cloudflared; then
    warn "cloudflared still running; disabling a module does not stop its service"
  fi
elif ! has cloudflared; then
  bad "cloudflared enabled but the binary is not installed"
else
  ok "cloudflared $(cloudflared --version 2>/dev/null | awk '{print $3}')"
  if unit_active cloudflared; then
    ok "cloudflared.service active"
  else
    bad "cloudflared installed but tunnel service inactive"
  fi
  if unit_enabled cloudflared; then
    ok "cloudflared.service enabled"
  else
    warn "cloudflared.service not enabled"
  fi
  if [[ -f /etc/systemd/system/cloudflared.service ]]; then
    ok "cloudflared host service unit present"
  else
    warn "cloudflared unit is not the postinstall host-service path"
  fi
  if [[ -f /etc/cloudflared/token ]]; then
    token_perms=$(stat -c '%a' /etc/cloudflared/token)
    if [[ $token_perms == 600 ]]; then
      ok "cloudflared token file mode 600"
    else
      bad "cloudflared token file mode $token_perms, wanted 600"
    fi
    token_owner=$(stat -c '%U:%G' /etc/cloudflared/token)
    if [[ $token_owner == root:root ]]; then
      ok "cloudflared token file owned by root"
    else
      bad "cloudflared token file owned by $token_owner, wanted root:root"
    fi
  else
    warn "no /etc/cloudflared/token, token may live in another service config"
  fi
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
