# sysctl

`/etc/sysctl.d/99-postinstall-hardening.conf`. all of it applies live via
`sysctl --system`, no reboot. numbers are boring, the reasons are not.

| key | value | why |
| --- | --- | --- |
| `kernel.dmesg_restrict` | 1 | unprivileged users cannot read the kernel ring buffer |
| `kernel.kptr_restrict` | 2 | kernel pointers show as zero in `/proc` |
| `kernel.yama.ptrace_scope` | 1 | a process can only ptrace its children |
| `kernel.unprivileged_bpf_disabled` | 1 | no bpf maps for unprivileged users |
| `net.core.bpf_jit_harden` | 2 | harden the bpf jit against spraying |
| `kernel.randomize_va_space` | 2 | full aslr |
| `fs.protected_hardlinks` | 1 | no hardlink tricks on files you do not own |
| `fs.protected_symlinks` | 1 | no symlink races in world-writable dirs |
| `fs.protected_fifos` | 2 | no fifo squatting in sticky dirs |
| `fs.protected_regular` | 2 | same for regular files in `/tmp` |
| `fs.suid_dumpable` | 0 | setuid crashes do not leave a core with secrets |
| `net.ipv4.conf.all.rp_filter` | 1 | reverse path filter, strict |
| `net.ipv4.conf.all.accept_redirects` | 0 | no icmp redirects rewriting routes |
| `net.ipv6.conf.all.accept_redirects` | 0 | same for v6 |
| `net.ipv4.conf.all.secure_redirects` | 0 | not even from the default gateway |
| `net.ipv4.conf.all.send_redirects` | 0 | we are not a router |
| `net.ipv4.conf.all.log_martians` | 1 | log impossible source addresses |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | no smurf amplifier |
| `net.ipv4.icmp_ignore_bogus_error_responses` | 1 | less log spam from broken stacks |
| `net.ipv4.tcp_syncookies` | 1 | syn flood survival |
| `net.ipv4.tcp_rfc1337` | 1 | drop timewait assassination attempts |

## what is deliberately missing

`net.ipv4.ip_forward = 1` is not set here. docker sets it itself, and a base
image script that forces it on a box without docker is just making a router.

`net.ipv6.conf.all.accept_ra = 0` is not set. plenty of providers hand out ipv6
prefixes over router advertisements. turning RA off is a great way to lose the
v6 address and spend an evening in the console.

`kernel.unprivileged_userns_clone` is not set to 0. rootless docker, chrome
sandboxes and half the modern tooling want user namespaces.

`vm.swappiness`, `vm.overcommit_memory`, `net.core.somaxconn`: application
tuning, not hardening. keep them out of a base script.

## checking

```bash
sudo sysctl --system
sysctl kernel.yama.ptrace_scope
sudo bash audit/debian13-audit.sh | sed -n '/== sysctl/,/== updates/p'
```

the audit reads the deployed file and compares each key with the running kernel,
so drift shows up as `FAIL` with both values.

if a key rejects a value on your kernel, compare with
`/usr/share/doc/linux-image-*/config` or `sysctl -a`. older kernels rarely
reject anything here, but cloud kernels do trim options.
