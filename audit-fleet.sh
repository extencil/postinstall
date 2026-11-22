#!/usr/bin/env bash
# audit every host in the pool, one at a time. ssh -t lets remote sudo prompt.
set -u

hosts_file=${1:-debian-hosts-pool.txt}
[[ -r $hosts_file ]] || { printf 'missing host file: %s\n' "$hosts_file" >&2; exit 1; }

while IFS= read -r host || [[ -n $host ]]; do
  host=${host%%[[:space:]]*}
  [[ -z $host || $host == \#* ]] && continue

  printf '\n=== %s ===\n' "$host"
  ssh -t -p 1 "extencil@$host" \
    'sudo bash /root/postinstall/audit/debian13-audit.sh --no-color' \
    || printf '[fail] %s\n' "$host"
done < "$hosts_file"
