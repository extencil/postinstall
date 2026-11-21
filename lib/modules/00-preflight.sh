#!/usr/bin/env bash
# module: preflight - sanity checks, clock, hostname, apt index.

module_preflight() {
  log_step "preflight"

  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root. try: sudo bash $0"
  command -v systemctl >/dev/null || die "systemd is required, this is not a container image builder"

  local id version
  id=$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}")
  version=$(debian_version_id)

  if [[ $id != debian ]]; then
    [[ ${ALLOW_UNSUPPORTED:-0} == 1 ]] || die "expected debian, found '$id'. set ALLOW_UNSUPPORTED=1 to ignore"
    log_warn "running on '$id', not debian. expect rough edges"
  elif [[ $version != 13 ]]; then
    [[ ${ALLOW_UNSUPPORTED:-0} == 1 ]] || die "expected debian 13 (trixie), found '$version'. set ALLOW_UNSUPPORTED=1 to ignore"
    log_warn "debian $version, not 13. script targets trixie"
  else
    log_ok "debian 13 ($DEBIAN_CODENAME)"
  fi

  if command -v cloud-init >/dev/null 2>&1; then
    log_warn "cloud-init detected. it may rewrite ssh config on boot, drop-ins here sort first so they win"
  fi

  apt_update

  if [[ -n ${TIMEZONE:-} ]]; then
    local current
    current=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    if [[ $current != "$TIMEZONE" ]]; then
      run timedatectl set-timezone "$TIMEZONE"
      log_ok "timezone -> $TIMEZONE"
    else
      log_skip "timezone already $TIMEZONE"
    fi
  fi

  # providers sometimes ship chrony already; timesyncd and chrony fight over
  # the time-daemon virtual package, so only install ours when nothing else is.
  if command -v chronyd >/dev/null 2>&1; then
    enable_now chrony
    log_skip "chrony already handles the clock"
  elif command -v ntpd >/dev/null 2>&1; then
    enable_now ntpsec 2>/dev/null || enable_now ntp
    log_skip "ntpd already handles the clock"
  else
    install_pkgs systemd-timesyncd
    enable_now systemd-timesyncd
  fi
  if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
    log_ok "clock synchronized"
  else
    log_warn "clock not synchronized yet, give timesyncd a minute"
  fi

  if [[ -n ${HOSTNAME_SET:-} ]] && [[ $(hostnamectl --static) != "$HOSTNAME_SET" ]]; then
    run hostnamectl set-hostname "$HOSTNAME_SET"
    log_ok "hostname -> $HOSTNAME_SET"
  fi
}
