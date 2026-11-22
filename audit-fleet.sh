#!/usr/bin/env bash
# audit every host in the pool, one at a time. ssh -t lets remote sudo prompt.
set -u

hosts_file=${1:-debian-hosts-pool.txt}
[[ -r $hosts_file ]] || { printf 'missing host file: %s\n' "$hosts_file" >&2; exit 1; }
[[ -t 0 ]] || { printf 'run from a terminal; sudo needs a PTY\n' >&2; exit 1; }

# fd 3 holds the list, so ssh keeps the terminal on stdin for the sudo prompt.
exec 3<"$hosts_file"
line=""
while IFS= read -r line <&3 || [[ -n $line ]]; do
  host=${line%%[[:space:]]*}
  [[ -z $host || $host == \#* ]] && continue

  printf '\n=== %s ===\n' "$host"
  ssh -t -p 1 "extencil@$host" \
    'sudo bash /root/postinstall/audit/debian13-audit.sh --no-color' \
    || printf '[fail] %s\n' "$host"
done
exec 3<&-
