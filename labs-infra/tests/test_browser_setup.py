#!/usr/bin/env python3
"""The logic behind `hk rancher --setup`, tested without touching this Mac.

The two things it changes — /etc/hosts and the system keychain — are host-wide
and need sudo, so the parts that decide WHAT to change are pure functions and
are tested here. Nothing in this file writes to either.
"""
import importlib.util
import pathlib
import subprocess
import sys
import tempfile
from importlib.machinery import SourceFileLoader

ROOT = pathlib.Path(__file__).resolve().parents[1]
loader = SourceFileLoader("hk_browser_setup", str(ROOT / "bin/hk-browser-setup"))
spec = importlib.util.spec_from_loader("hk_browser_setup", loader)
bs = importlib.util.module_from_spec(spec)
loader.exec_module(bs)

IP, HOST = "192.168.56.111", "rancher.hk.test"
PASSED = FAILED = 0


def check(name, got, want):
    global PASSED, FAILED
    if got == want:
        PASSED += 1
        print(f"  \033[32mok\033[0m    {name}")
    else:
        FAILED += 1
        print(f"  \033[31mFAIL\033[0m  {name}\n          got:  {got!r}\n          want: {want!r}")


def raises(name, fn, *args):
    global PASSED, FAILED
    try:
        fn(*args)
    except (ValueError, RuntimeError):
        PASSED += 1
        print(f"  \033[32mok\033[0m    {name}")
        return
    FAILED += 1
    print(f"  \033[31mFAIL\033[0m  {name} — no error raised")


print("labs.yml is the single source of truth")
check("mgmt.ip", bs.field("mgmt", "ip"), "192.168.56.111")
check("mgmt.name", bs.field("mgmt", "name"), "hk-mgmt")
check("vm.ip is not confused with mgmt.ip", bs.field("vm", "ip"), "192.168.56.110")
check("rancher.hostname", bs.field("rancher", "hostname"), "rancher.hk.test")

print("/etc/hosts is edited surgically")
check("adds a missing entry",
      bs.update_hosts("127.0.0.1 localhost\n", IP, HOST),
      "127.0.0.1 localhost\n192.168.56.111 rancher.hk.test\n")
once = bs.update_hosts("127.0.0.1 localhost\n", IP, HOST)
check("re-running changes nothing", bs.update_hosts(once, IP, HOST), once)
check("corrects a stale address instead of adding a second line",
      bs.update_hosts("10.0.0.9 rancher.hk.test\n", IP, HOST),
      "192.168.56.111 rancher.hk.test\n")
check("keeps other aliases sharing the line",
      bs.update_hosts("10.0.0.9 other.test rancher.hk.test\n", IP, HOST),
      "10.0.0.9\tother.test\n192.168.56.111 rancher.hk.test\n")
check("leaves unrelated entries alone",
      bs.update_hosts("1.2.3.4 unrelated.test\n", IP, HOST),
      "1.2.3.4 unrelated.test\n192.168.56.111 rancher.hk.test\n")
check("keeps comments on an otherwise emptied line",
      bs.update_hosts("10.0.0.9 rancher.hk.test # note\n", IP, HOST),
      "# note\n192.168.56.111 rancher.hk.test\n")
raises("rejects a non-IPv4 address", bs.update_hosts, "", "999.1.1.1", HOST)
raises("rejects a malformed hostname", bs.update_hosts, "", IP, "Not A Host")

real = pathlib.Path("/etc/hosts").read_text()
rewritten = bs.update_hosts(real, IP, HOST)
check("this Mac's real /etc/hosts keeps every unrelated line",
      all(l in rewritten for l in real.splitlines() if l.strip() and HOST not in l), True)
check("this Mac's real /etc/hosts is stable on a second pass",
      bs.update_hosts(rewritten, IP, HOST), rewritten)

print("superseded lab CAs are found by digest, never by name")
tmp = tempfile.mkdtemp()


def make_ca(name, cn="Hacking Kubernetes Lab Rancher CA"):
    crt = f"{tmp}/{name}.crt"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-sha256", "-days", "5", "-keyout", f"{tmp}/{name}.key",
                    "-out", crt, "-subj", f"/CN={cn}"], check=True, capture_output=True)
    return pathlib.Path(crt).read_text()


old_ca, new_ca = make_ca("old"), make_ca("new")
other = make_ca("other", cn="Some Other Root")

stale = bs.superseded_certificates(old_ca + "\n" + new_ca, new_ca)
check("one stale CA is found", len(stale), 1)
check("the stale one is the old CA", stale[0], bs.certificate_digests(old_ca)[0])
check("the CA in use is never removed", bs.certificate_digests(new_ca)[0] in stale, False)
check("nothing stale when only the current CA is trusted",
      bs.superseded_certificates(new_ca, new_ca), [])
check("an empty keychain listing is safe", bs.superseded_certificates("", new_ca), [])
check("three rebuilds leave two stale CAs",
      len(bs.superseded_certificates(old_ca + new_ca + make_ca("older"), new_ca)), 2)
check("a duplicate listing is not counted twice",
      len(bs.superseded_certificates(old_ca + "\n" + old_ca + "\n" + new_ca, new_ca)), 1)
# prune_superseded_cas filters the listing by common name BEFORE this runs, so
# this only records that a differently-named root reaching it would be caught
# by digest rather than silently trusted.
check("a differently-named root is still judged by digest",
      bs.certificate_digests(other)[0] in bs.superseded_certificates(other + new_ca, new_ca), True)

print(f"\n{PASSED} passed, {FAILED} failed")
sys.exit(1 if FAILED else 0)
