#!/usr/bin/env bash
# Every check that needs no virtual machine. Run it before building anything:
#
#   tests/run.sh
#
# It starts no VM, changes nothing on this Mac, and touches no cluster. The
# commands that would — `hk build`, `hk destroy` — are exercised against a stub
# `vagrant` in tests/stub-bin that only records what it was asked to do.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

for suite in test_repo.sh test_hk_cli.sh; do
  printf '\n\033[1m=== %s ===\033[0m\n' "$suite"
  bash "$ROOT/tests/$suite" || rc=1
done

for suite in test_browser_setup.py test_cards.py; do
  printf '\n\033[1m=== %s ===\033[0m\n' "$suite"
  python3 "$ROOT/tests/$suite" || rc=1
done

printf '\n'
if [ "$rc" -eq 0 ]; then
  printf '\033[32mAll offline checks passed.\033[0m\n'
else
  printf '\033[31mSome checks failed.\033[0m\n'
fi
exit "$rc"
