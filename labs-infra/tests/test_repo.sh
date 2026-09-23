#!/usr/bin/env bash
# Everything that can be checked without a VM: syntax, and the agreements
# between labs.yml, the Vagrantfile, the playbooks and bin/hk.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
try() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

echo "syntax"
for f in bin/hk tests/test_hk_cli.sh tests/test_repo.sh tests/stub-bin/*; do
  try "bash -n $f" "bash -n '$f'"
done
for f in bin/make-inventory bin/extract-labs.py bin/hk-browser-setup tests/test_browser_setup.py; do
  try "python compiles $f" "python3 -m py_compile '$f'"
done
try "Vagrantfile is valid" "vagrant validate"

echo "playbooks"
export ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"
printf '[labvm]\nhk-labs ansible_host=127.0.0.1\n\n[mgmtvm]\nhk-mgmt ansible_host=127.0.0.1\n' > /tmp/hk-test-inv.ini
for pb in site.yml lab.yml mgmt.yml import.yml; do
  try "$pb parses" "ansible-playbook --syntax-check -i /tmp/hk-test-inv.ini 'ansible/$pb'"
done
rm -f /tmp/hk-test-inv.ini

echo "every role a playbook names exists"
for role in $(grep -rhoE '^\s+- role: [a-z0-9_]+' ansible/*.yml | awk '{print $3}' | sort -u); do
  if [ -f "ansible/roles/$role/tasks/main.yml" ]; then ok "role $role"; else bad "role $role missing"; fi
done

echo "labs.yml agrees with everything that reads it"
try "Vagrantfile reads both machines" "grep -q \"SPEC.fetch('mgmt')\" Vagrantfile"
for key in "vm name" "vm ip" "mgmt name" "mgmt ip" "rancher hostname" "rancher admin_password"; do
  set -- $key
  v="$(awk -v top="^$1:" -v k="^  $2:" '$0~top{f=1;next} f&&/^[a-z]/{f=0} f&&$0~k{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' labs.yml)"
  if [ -n "$v" ]; then ok "labs.yml $1.$2 = $v"; else bad "labs.yml $1.$2 is unreadable by bin/hk's parser"; fi
done
labs_n=$(grep -cE '^  - id: [0-9]+' labs.yml)
try "labs.yml lists 11 labs (found $labs_n)" "[ '$labs_n' -eq 11 ]"

echo "every lab in labs.yml has a kit on disk"
for id in $(awk '/^  - id: /{print $3}' labs.yml); do
  d=$(printf 'ansible/roles/labkit/files/lab%02d' "$id")
  if [ -f "$d/LAB.md" ]; then ok "kit for lab$(printf '%02d' "$id")"; else bad "no kit at $d"; fi
done

echo "the lab step scripts can actually run"
# stepNN.sh runs in a CHILD bash. Shell functions are not inherited unless
# exported, so without this every lab's first command dies with
# "k: command not found" while the same line typed by hand works.
helpers=ansible/roles/common/templates/hk-labs.sh.j2
try "k, new_lab and lab are exported to child shells" \
  "grep -qE '^export -f k new_lab lab' $helpers"
# hk deploy creates the namespace; Lab 0's plain \`create\` would then fail on
# the first step of every deployed lab.
try "new_lab tolerates a namespace that already exists" \
  "grep -q 'if ! k get namespace' $helpers"
try "new_lab reasserts labels rather than failing on them" \
  "grep -q -- '--overwrite' $helpers"
for f in ansible/roles/labkit/files/lab*/step*.sh; do
  head -1 "$f" | grep -q 'bash' || bad "$f is not a bash script" "exported functions reach bash children only"
done
ok "every step script is bash, so exported functions reach it"

echo "every lab has a question card"
for id in $(awk '/^  - id: /{print $3}' labs.yml); do
  f=$(printf 'questions/lab%02d.yml' "$id")
  if [ -f "$f" ]; then ok "card $f"; else bad "no question card at $f"; fi
done
# extract-labs.py rmtree's the kit directory, so a card stored there would be
# destroyed the next time the kits are regenerated from theory.md.
if ls ansible/roles/labkit/files/lab*/questions.yml >/dev/null 2>&1; then
  bad "a question card is inside the generated kit tree" "it will be deleted by extract-labs.py"
else
  ok "no question card lives in the generated kit tree"
fi

echo "no lab has grown a second-node requirement"
# The lab cluster is deliberately one node. A lab kit regenerated from an
# edited theory.md could quietly introduce scheduling constructs that need
# more, and it would fail at study time rather than here. Reads of
# .spec.nodeName are fine — labs 9 and 10 report which node ran a Pod.
multinode=$(grep -rlnE 'nodeSelector|affinity:|topologyKey|tolerations:|kubectl (drain|cordon)|replicas: [2-9]' \
  ansible/roles/labkit/files/lab*/ 2>/dev/null || true)
if [ -z "$multinode" ]; then
  ok "no lab kit needs more than one node"
else
  bad "a lab kit now needs more than one node" "$multinode"
fi

echo "the two machines cannot collide"
vm_ip="$(awk '/^vm:/{f=1;next} f&&/^  ip:/{print $2;exit}' labs.yml)"
mg_ip="$(awk '/^mgmt:/{f=1;next} f&&/^  ip:/{print $2;exit}' labs.yml)"
try "lab and management addresses differ" "[ '$vm_ip' != '$mg_ip' ]"
vm_nm="$(awk '/^vm:/{f=1;next} f&&/^  name:/{print $2;exit}' labs.yml)"
mg_nm="$(awk '/^mgmt:/{f=1;next} f&&/^  name:/{print $2;exit}' labs.yml)"
try "lab and management names differ" "[ '$vm_nm' != '$mg_nm' ]"

echo "generated lab kits still match theory.md"
tmp="$(mktemp -d)"
mkdir -p "$tmp/labs-infra/bin"
cp ../theory.md "$tmp/" && cp bin/extract-labs.py "$tmp/labs-infra/bin/"
if (cd "$tmp/labs-infra" && python3 bin/extract-labs.py >/dev/null 2>&1); then
  if diff -rq "$tmp/labs-infra/ansible/roles/labkit/files" ansible/roles/labkit/files >/dev/null 2>&1; then
    ok "extract-labs.py reproduces the checked-in kits"
  else
    bad "lab kits differ from theory.md" "re-run bin/extract-labs.py"
  fi
else
  bad "extract-labs.py failed to run"
fi
rm -rf "$tmp"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
