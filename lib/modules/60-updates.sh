#!/usr/bin/env bash
# module: updates - unattended security upgrades, not the reboot at 3am kind.

module_updates() {
  log_step "unattended upgrades"

  install_pkgs unattended-upgrades apt-listchanges needrestart

  write_file /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  # 52- sorts after the stock 50unattended-upgrades, so these values win
  # without throwing away the package's own defaults.
  write_file /etc/apt/apt.conf.d/52postinstall-unattended-upgrades 0644 <<EOF
// managed by postinstall - edit the script, not this file
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=$DEBIAN_CODENAME,label=Debian";
        "origin=Debian,codename=$DEBIAN_CODENAME,label=Debian-Security";
        "origin=Debian,codename=$DEBIAN_CODENAME-security,label=Debian-Security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF

  enable_now unattended-upgrades
  run systemctl restart unattended-upgrades
  if systemctl list-timers apt-daily-upgrade.timer --no-legend 2>/dev/null | grep -q apt-daily-upgrade; then
    log_ok "apt-daily-upgrade.timer armed"
  else
    log_warn "apt-daily-upgrade.timer not listed, check systemctl list-timers"
  fi

  if [[ -f /var/run/reboot-required ]]; then
    log_warn "host wants a reboot (kernel or libc). do it when you have a quiet minute"
  fi
}
