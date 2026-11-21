#!/usr/bin/env bash
# module: firewall - nftables, default drop, ssh + whatever you opted into.
# runs before the ssh module so the new port is open before sshd moves.

module_firewall() {
  log_step "firewall (nftables)"

  install_pkgs nftables

  local ufw_disabled=0
  if service_active ufw; then
    run systemctl disable --now ufw
    ufw_disabled=1
    log_ok "ufw disabled, nftables owns the ruleset now"
  fi

  local tcp_ports=${SSH_PORT:-22} udp_ports=""
  [[ -n ${EXTRA_TCP_PORTS:-} ]] && tcp_ports="$tcp_ports ${EXTRA_TCP_PORTS//,/ }"
  [[ -n ${EXTRA_UDP_PORTS:-} ]] && udp_ports=${EXTRA_UDP_PORTS//,/ }

  local tcp_line udp_line
  tcp_line="        tcp dport { $tcp_ports } accept"
  if [[ -n $udp_ports ]]; then
    udp_line="        udp dport { $udp_ports } accept"
  else
    udp_line="        # no extra udp ports configured"
  fi

  write_file /etc/nftables.conf 0644 <<EOF
#!/usr/sbin/nft -f
# managed by postinstall - edit the script, not this file
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop

        meta l4proto icmp accept
        meta l4proto ipv6-icmp accept

$tcp_line
$udp_line
    }

    chain forward {
        type filter hook forward priority filter; policy drop;

        ct state established,related accept

        # docker bridges. docker writes its own rules in table ip, but a
        # packet still has to survive this chain, so let the bridges through.
        iifname "docker0" accept
        oifname "docker0" accept
        iifname "br-*" accept
        oifname "br-*" accept
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF

  run nft -c -f /etc/nftables.conf || die "nftables config failed validation, nothing applied"

  if [[ $LAST_WRITE_CHANGED == 1 ]] || [[ $ufw_disabled == 1 ]] || ! service_active nftables; then
    enable_now nftables
    run systemctl restart nftables
    log_ok "ruleset applied (${tcp_ports// /, })"
    # flush ruleset nuked docker's rules; docker puts them back on restart.
    if service_active docker; then
      run systemctl restart docker
      log_ok "docker restarted to re-add its iptables rules"
    fi
    if service_active fail2ban; then
      run systemctl restart fail2ban
      log_ok "fail2ban restarted to re-add its bans"
    fi
  else
    log_skip "ruleset unchanged"
  fi
}
