# GEMINI.md

canonical agent instructions, read this first:

@AGENTS.md

the repo deploys debian 13 vps hardenings. the short version:

- `debian13-postinstall.sh` applies, `audit/debian13-audit.sh` verifies.
- modules live in `lib/modules/`, are idempotent and non-interactive, and
  mutate only through `run()`; config writes only through `write_file`.
- adding a module means: file, entrypoint `case`, config default + example,
  README row, doc, audit check, changelog.
- never weaken the ssh lockout guard, never add password auth defaults,
  never commit tokens.
- gates: `bash -n`, `shellcheck -x`, `--list`, and `--dry-run` on a disposable
  debian 13 host only.
