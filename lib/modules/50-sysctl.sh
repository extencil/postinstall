#!/usr/bin/env bash
# module: sysctl - kernel and network knobs that cost nothing to turn on.

module_sysctl() {
  log_step "sysctl hardening"

  write_file /etc/sysctl.d/99-postinstall-hardening.conf 0644 <<'EOF'
# managed by postinstall - edit the script, not this file

# information leaks
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# memory layout
kernel.randomize_va_space = 2

# filesystem races
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0

# network sanity
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1

# left alone on purpose: ip_forward (docker needs it), accept_ra (some vps
# providers hand out ipv6 over RA and killing it drops your v6),
# unprivileged_userns_clone (docker rootless, chrome sandboxes).
EOF

  if ((DRY_RUN)); then
    log_dry "sysctl --system"
    return 0
  fi

  # a kernel that does not know one key should not abort the rest.
  if ! sysctl -q --system 2>/tmp/postinstall-sysctl; then
    log_warn "sysctl complained, unknown keys are normal on older kernels:"
    sed 's/^/      /' /tmp/postinstall-sysctl >&2
  fi

  local bad=0
  while IFS=' = ' read -r key value; do
    [[ -z $key || $key == \#* ]] && continue
    local current
    current=$(sysctl -n "$key" 2>/dev/null || printf '?')
    [[ $current == "$value" ]] || { bad=$((bad + 1)); log_warn "$key is $current, wanted $value"; }
  done < <(grep -E '^[a-z]' /etc/sysctl.d/99-postinstall-hardening.conf)

  if ((bad == 0)); then
    log_ok "all sysctl values applied"
  else
    log_warn "$bad value(s) did not stick, see audit output"
  fi
}
