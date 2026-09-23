#!/usr/bin/env bash
# What `hk` would run, asserted without touching a VM.
#
# tests/stub-bin holds a fake `vagrant` and `ansible-playbook` that record
# their arguments to $STUB_LOG. Putting that directory first on PATH lets every
# dispatch path be exercised — including `hk destroy`, which is the one command
# that must never be tested for real.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

# `hk` under the stubs, with a fresh log. Args after the marker are the command.
hk_run() {
  local running="$1"; shift
  STUB_LOG="$(mktemp)"; STUB_STATE="$(mktemp)"
  STUB_RUNNING="$running" PATH="$ROOT/tests/stub-bin:$PATH" \
    STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" \
    "$ROOT/bin/hk" "$@" >/dev/null 2>&1
  HK_RC=$?
  HK_LOG="$(cat "$STUB_LOG")"
  rm -f "$STUB_LOG" "$STUB_STATE"
}

ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

logged()     { grep -qF -- "$2" <<<"$1"; }
assert_log() { if logged "$HK_LOG" "$2"; then ok "$1"; else bad "$1" "not in log: $2"; fi; }
assert_not() { if logged "$HK_LOG" "$2"; then bad "$1" "unexpectedly ran: $2"; else ok "$1"; fi; }
assert_rc()  { if [ "$HK_RC" -eq "$2" ]; then ok "$1"; else bad "$1" "exit $HK_RC, wanted $2"; fi; }

echo "hk build"
hk_run "" build labs
assert_log "build labs boots the lab VM"        "vagrant up hk-labs"
assert_not "build labs does not boot hk-mgmt"   "vagrant up hk-mgmt"
assert_log "build labs runs site.yml"           "ansible/site.yml"

hk_run "" build mgmt
assert_log "build mgmt boots the management VM" "vagrant up hk-mgmt"
assert_not "build mgmt does not boot hk-labs"   "vagrant up hk-labs"
assert_log "build mgmt runs mgmt.yml"           "ansible/mgmt.yml"

hk_run "hk-labs hk-mgmt" build
assert_log "bare build boots the lab VM"        "vagrant up hk-labs"
assert_log "bare build boots the management VM" "vagrant up hk-mgmt"
assert_log "bare build runs site.yml"           "ansible/site.yml"
assert_log "bare build runs mgmt.yml"           "ansible/mgmt.yml"
assert_log "bare build imports the cluster"     "ansible/import.yml"

hk_run "" build nonsense
assert_rc "build rejects an unknown target" 2

echo "hk destroy"
hk_run "" destroy
assert_log "bare destroy removes the lab VM"        "vagrant destroy -f hk-labs"
assert_log "bare destroy removes the management VM" "vagrant destroy -f hk-mgmt"
assert_rc  "bare destroy does not ask and succeeds" 0

hk_run "" destroy labs
assert_log "destroy labs removes the lab VM"          "vagrant destroy -f hk-labs"
assert_not "destroy labs spares the management VM"    "vagrant destroy -f hk-mgmt"

hk_run "" destroy mgmt
assert_log "destroy mgmt removes the management VM"   "vagrant destroy -f hk-mgmt"
assert_not "destroy mgmt spares the lab VM"           "vagrant destroy -f hk-labs"

hk_run "" mgmt destroy
assert_log "hk mgmt destroy routes to destroy mgmt"   "vagrant destroy -f hk-mgmt"
assert_not "hk mgmt destroy spares the lab VM"        "vagrant destroy -f hk-labs"

hk_run "" destroy nonsense
assert_rc "destroy rejects an unknown target" 2

# The record must be removed while the agent can still be reached, but ONLY
# when Rancher survives the same command.
hk_run "hk-labs hk-mgmt" destroy labs
assert_log "destroy labs unimports first" "ansible/import.yml"
hk_run "hk-labs hk-mgmt" destroy
assert_not "bare destroy skips the unimport" "ansible/import.yml"

echo "hk lab names"
for variant in lab04 lab4 04 4; do
  hk_run "hk-labs" deploy "$variant"
  if logged "$HK_LOG" "hk_lab_ref=lab04"; then ok "deploy $variant -> lab04"; else bad "deploy $variant -> lab04"; fi
done
hk_run "hk-labs" deploy 11
assert_rc "deploy rejects lab 11" 2
hk_run "hk-labs" deploy
assert_rc "deploy with no lab is rejected" 2

echo "hk run stages and runs"
hk_run "hk-labs" run lab04
assert_log "run stages the lab first" "hk_lab_ref=lab04"
assert_log "run stages with the deploy action" "hk_action=deploy"
for variant in lab04 04 4; do
  hk_run "hk-labs" run "$variant"
  if logged "$HK_LOG" "hk_lab_ref=lab04"; then ok "run $variant -> lab04"; else bad "run $variant -> lab04"; fi
done
hk_run "hk-labs" run 11
assert_rc "run rejects lab 11" 2
hk_run "" run lab04
assert_rc "run needs the lab VM running" 1

echo "hk guards"
hk_run "" deploy lab01
assert_rc  "deploy needs the lab VM running" 1
assert_not "deploy without the VM runs no playbook" "ansible/lab.yml"
hk_run "hk-labs" import
assert_rc "import needs the management VM" 1
hk_run "" mgmt configure
assert_rc "mgmt configure needs the management VM" 1
hk_run "hk-labs" unimport
assert_rc "unimport works without the management VM" 0

echo "hk rancher"
hk_run "hk-mgmt" rancher
assert_rc "rancher prints the login" 0
hk_run "hk-mgmt" rancher --print-setup
assert_rc "rancher --print-setup works" 0
hk_run "hk-mgmt" rancher --nonsense
assert_rc "rancher rejects an unknown flag" 2

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
