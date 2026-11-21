# CLAUDE.md

this repo keeps one canonical instruction file for every agent:

@AGENTS.md

read it before editing. short version of the rules that matter most:

- debian 13 only. bash + systemd + apt, no build step, no ci.
- modules are idempotent, non-interactive, and mutate only through `run()`.
  config files are written only through `write_file`, which backs up first.
- a new module needs the entrypoint `case` arm, a config default, a README
  row, a doc update, an audit check and a changelog line.
- never weaken the ssh lockout guard or add password auth defaults.
- testing gates: `bash -n`, `shellcheck -x`, `--list`, `--help`, and a full
  `--dry-run` only on a disposable debian 13 vm.
