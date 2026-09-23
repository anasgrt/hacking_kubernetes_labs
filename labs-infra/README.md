# Hacking Kubernetes — lab infrastructure

One virtual machine, built once, carrying every capability the labs need.
Labs are deployed into it one at a time and removed when you are finished.
The lab content comes from `../theory.md`, which this directory never modifies.

A second, **optional** virtual machine runs RKE2 with Rancher on top, so the
lab cluster and each deployed lab can be watched through a real UI. It is never
a lab target. Everything else here works without it — build it only if you want
the view. See [Watching the labs in Rancher](#watching-the-labs-in-rancher).

## The two machines

| | `hk-labs` | `hk-mgmt` |
| --- | --- | --- |
| Holds | Docker, k3s, gVisor, Falco | RKE2, Rancher |
| Address | `192.168.56.110` | `192.168.56.111` |
| Wants | 6 GB, 4 vCPU | 10 GB, 4 vCPU |
| Built by | `hk build` | `hk mgmt build` |
| Required? | yes | no |
| Role | the labs run here, and attack it | watches, and is never attacked |

`vagrant up` with no argument brings up the lab VM alone, so nobody grows a
10 GB Rancher machine by accident. Why they are not one machine is in
[Two machines, on purpose](#two-machines-on-purpose).

## How it works

Vagrant and Ansible stay separate tools with separate jobs — the `Vagrantfile`
declares no provisioner. `hk build` runs both in sequence so you only type one
command.

| Step | Tool | What it does | Command |
| --- | --- | --- | --- |
| 1 | Vagrant | Creates a bare Ubuntu VM. Nothing installed. | `hk build` |
| 2 | Ansible | Installs Docker, k3s, gVisor and Falco into it. | (same command) |
| Then | Ansible | Deploys one lab into the configured VM. | `hk deploy lab01` |

`hk configure` re-runs step 2 on its own when you want it. The management VM
follows the same two steps under `hk mgmt build` and `hk mgmt configure`.

The seam between Vagrant and Ansible is `bin/make-inventory`, which reads
`vagrant ssh-config` and writes an Ansible inventory with a group per machine.
Because of it you can rebuild a box without re-running Ansible, and re-run
Ansible as often as you like without touching the box. It refuses, naming the
command that fixes it, when a playbook needs a machine that is not running.

## Getting started

### 1. Host tools, once

```bash
brew install --cask virtualbox vagrant
brew install ansible
```

Ansible runs **on the host**, not in the guest. Check all three:

```bash
VBoxManage --version     # 7.1.7 or newer
vagrant --version        # 2.4.x
ansible --version        # core 2.21+
```

On Apple Silicon, VirtualBox must be an arm64 build and the box an arm64 box;
an amd64 box will not boot. Tested: VirtualBox 7.1.7, Vagrant 2.4.2,
ansible-core 2.21, `bento/ubuntu-24.04` `202502.21.0`.

### 2. Build everything

```bash
cd labs-infra
bin/hk build
```

One command, about 35 minutes: the lab VM, the management VM, the Rancher
link, and this Mac's access to Rancher. It asks for your Mac password near the
end — that is the only step that touches your own machine, and it runs last, so
nothing is changed here until both VMs are proven healthy.

Narrow it when you want one machine:

```bash
bin/hk build labs    # the lab VM only, ~15 min — every lab works with just this
bin/hk build mgmt    # the management VM only, ~20 min
```

`hk build labs` is two steps. First Vagrant clones the base box, boots it, and
attaches a host-only NIC at `192.168.56.110` — about a minute. Then
`bin/make-inventory` reads `vagrant ssh-config` and Ansible runs
`ansible/site.yml` over SSH:

1. Base packages and the Docker engine; pre-pulls the pinned
   `python:3.13-slim` digest.
2. Picks a DNS upstream for the cluster that demonstrably answers, and proves
   it — see [Cluster DNS](#cluster-dns).
3. k3s — waits for the node and CoreDNS, creates the `study*` namespaces the
   chapter examples use, pulls the study image straight into containerd.
4. gVisor — installs `runsc`, wires it into k3s's containerd, creates the
   `gvisor` RuntimeClass, then **launches a real sandboxed Pod to prove it**.
5. Falco — installs the sensor on the modern eBPF driver, then **triggers a
   real shell and waits for the alert** before declaring success.
6. Runs `hk-lab check` and fails if any capability is unmet.

Ten to fifteen minutes the first time. Safe and quick to re-run: `bin/hk build`
on an existing VM skips straight to the Ansible half, and every role is
idempotent. `bin/hk configure` runs the Ansible half alone.

Save a restore point once it finishes:

```bash
bin/hk snapshot
```

### 3. Deploy a lab

```bash
bin/hk deploy lab01
bin/hk ssh
```

Deploying creates the lab's namespaces under the Restricted Pod Security
Standard and puts its manifests and step scripts in `~/labs/lab01/`. It does
**not** run the lab's commands — working through those is the exercise.

Inside the VM: `lab 1` jumps to that directory, `k` and `new_lab` from Lab 0
are already defined, and `LAB_CONTEXT` is pinned to the VM's only context so
Lab 0's selection menu is unnecessary.

### 4. Finish and move on

```bash
bin/hk remove lab01      # take it out of the VM
bin/hk deploy lab02      # next
```

## Commands

```bash
# the lab VM
bin/hk build             # build EVERYTHING: both machines + this Mac's access
bin/hk build labs        # the lab VM only
bin/hk build mgmt        # the management VM only
bin/hk configure         # re-run the Ansible half only
bin/hk check             # re-check its capabilities
bin/hk ssh               # shell into it
bin/hk snapshot          # save a restore point
bin/hk restore           # roll back to it
bin/hk stop              # shut down, keep the disk
bin/hk destroy           # delete EVERYTHING: both machines, no questions
bin/hk destroy labs      # delete the lab VM only
bin/hk destroy mgmt      # delete the management VM only

# labs, inside the VM
bin/hk list              # every lab and whether it is deployed
bin/hk deploy lab04      # add a lab
bin/hk status lab04      # what it has created so far
bin/hk reset lab04       # clear what it created, keep it deployed
bin/hk remove lab04      # take it out entirely
bin/hk run 04            # run its steps so its resources exist
bin/hk question 04       # what that lab asks
bin/hk solution 04       # the answers

# the management VM — optional
bin/hk mgmt build        # create it and install RKE2 + Rancher
bin/hk mgmt configure    # re-run the Ansible half only
bin/hk mgmt check        # is Rancher up and reachable
bin/hk mgmt destroy      # delete it; the labs are unaffected
bin/hk import            # register the lab cluster with Rancher
bin/hk unimport          # remove it from Rancher again
bin/hk rancher           # the URL and login
```

A lab may be written `lab04`, `lab4`, `04` or `4`. `bin/hk` alone prints this.

## Watching the labs in Rancher

Optional, and independent of everything above. A second VM runs RKE2 with
Rancher on it; the lab cluster is registered with that Rancher, and each
deployed lab becomes a Project in it.

`bin/hk build` already does all of this. These are the same steps
individually, for when you added the management VM later:

```bash
bin/hk build mgmt        # create the VM, install RKE2 and Rancher  (~20 min)
bin/hk import            # register the lab cluster with it
bin/hk rancher --setup   # give this Mac hostname resolution and CA trust
bin/hk rancher           # the URL and login
```

`hk mgmt build` is the same two steps as `hk build`: Vagrant makes a bare
machine at `192.168.56.111`, then Ansible installs RKE2, generates a private
CA, issues Rancher a certificate for `rancher.hk.test`, installs the pinned
Rancher chart, and **verifies an HTTPS login** before reporting success.

`hk import` registers the lab cluster. It teaches the lab VM and its CoreDNS
how to reach `rancher.hk.test`, installs the Rancher agent into k3s, waits for
Rancher to report the cluster active, and then **waits for Rancher's admission
webhook and proves a namespace can still be created** — see
[What importing actually costs](#what-importing-actually-costs).

After it, `hk deploy lab04` also creates Rancher Project `lab04` and moves
`hk-lab04` into it; `hk remove lab04` deletes the Project again.

### Opening it in a browser

`bin/hk build` does this for you; `bin/hk rancher --setup` does it on its own.

The VM has everything it needs. Your **Mac** needs two things Rancher cannot
give it: a way to resolve `rancher.hk.test`, and trust in the lab CA. Both are
host-wide changes that need `sudo`, so they are the one part of this repository
that will ask for your password.

```bash
bin/hk rancher --setup
```

It refuses to change anything until it has fetched the CA and confirmed Rancher
answers `/ping` over HTTPS with that CA, supplying the address by hand. Then it:

- adds `192.168.56.111 rancher.hk.test` to `/etc/hosts`, **replacing only that
  hostname** — other aliases on the same line, and every unrelated entry, are
  kept, and the original is backed up to `/etc/hosts.hk-backup.*`;
- trusts the lab CA for SSL in the system keychain, if it is not already;
- **removes the lab CAs an earlier `hk-mgmt` left behind.** Rebuilding the
  management VM mints a new CA under the same name, and macOS only ever *adds*
  trust, so without this every rebuild leaves another trusted root and the
  browser fails against a dead one. Certificates are matched by digest, never
  by name: the current CA, and anything with another subject, are never
  touched;
- checks `https://rancher.hk.test/ping` again through this Mac's own resolver
  and trust store, with no overrides — the same path the browser takes.

Re-running it is safe and changes nothing once it is correct. It supports
macOS; on Linux, add the hosts entry and import `hk-rancher-ca.crt` through
your distribution's or browser's certificate manager. `bin/hk rancher
--print-setup` prints the manual steps.

Then sign in as `admin` with the password from `bin/hk rancher`. The lab
cluster is under **Cluster Management** as `hk-labs`, beside the management
cluster `local`. Each deployed lab is a Project inside `hk-labs`.

A health check inside the VM cannot prove browser access: `hk mgmt check` uses
the VM's own hosts file and trust store. `DNS_PROBE_FINISHED_NXDOMAIN` means
the hosts entry is missing; a certificate warning means the CA is not trusted
or a stale one is shadowing it. Chrome and Opera cache both errors for the
session, so quit fully and reopen after fixing either.

### Two machines, on purpose

RKE2 and k3s both default to port 6443, to pod CIDR `10.42.0.0/16` and to
service CIDR `10.43.0.0/16`, and both run a CNI and iptables rules in the host
network namespace. The ports and CIDRs could be moved. Canal and kube-router
sharing one network namespace could not be made trustworthy — and Lab 4 exists
precisely because k3s's kube-router genuinely *enforces* NetworkPolicy. A
second machine costs 10 GB of RAM and removes the whole class of problem.

It also keeps the management plane out of the blast radius. Labs 3 and 7 are
about RBAC escalation and admission control; a Rancher sharing their cluster
would be both a distraction and a casualty.

### One cluster, so Projects rather than clusters

All eleven labs share one k3s cluster, so there is one cluster record in
Rancher for all of them. The per-lab unit is a Rancher **Project**, which the
lab's namespaces join through the `field.cattle.io/projectId` annotation — the
same mechanism the UI uses when you move a namespace by hand.

Set `rancher.lab_projects: false` in `labs.yml` to leave lab namespaces
ungrouped; the cluster itself stays imported either way.

### What importing actually costs

Not importing costs nothing. If the management VM was never built, `hk deploy`
and `hk remove` behave exactly as before — the Project step notices there is no
link and skips. `hk unimport` does not need the management VM either, so a
broken or deleted Rancher never blocks cleaning up the lab cluster.

Importing is not free, and the price is worth stating plainly. Registering a
cluster installs Rancher's `rancher.cattle.io` ValidatingWebhookConfiguration
into it, and its namespace rules use `failurePolicy: Fail`. From then on,
**creating a namespace in the lab cluster requires `rancher-webhook` to be
serving**. That is inherent to importing a cluster into Rancher, not a choice
this repository makes, and it cannot be designed away while the cluster is
registered.

What is done about it:

- `hk import` does not return until the webhook is serving *and* a real
  namespace create has succeeded. Rancher reports a cluster active well before
  its webhook has endpoints, so waiting on the cluster state alone would hand
  back a cluster whose next `hk deploy` fails.
- `hk deploy` retries namespace creation and labelling for five minutes, so a
  webhook that is restarting delays a lab rather than failing it.
- `hk unimport` removes the webhook with the rest of the agent, returning the
  cluster to exactly how it behaved before.

Labs 3 and 7 are the ones to be aware of: they are about RBAC and admission
control, and an imported cluster has an extra admission webhook in it that the
book's text does not mention. Run those two on an unimported cluster if you
want the environment the chapter describes.

The admin password is reapplied from `labs.yml` on every `hk mgmt configure`,
so a password changed in the UI lasts only until the next one. That is a
deliberate choice for a local teaching environment and nothing else: the
credential is in a file in the repository and printed by `hk rancher`.

## Running a lab

`hk deploy` stages a lab: it creates the namespace, assigns it to a Rancher
Project and puts the files in place. It does **not** run the lab's commands —
working through those is the exercise, so a freshly deployed lab has no
workloads and its Project in Rancher is empty. That is correct, and it
surprises everyone once.

When you want the resources to exist — to see a lab in Rancher, or to get back
to a known state quickly — run it:

```bash
bin/hk run 04              # run the lab, keep what it creates
bin/hk deploy lab04 --run  # deploy and run in one go
bin/hk run 04 --cleanup    # also run its final teardown step
```

Four things make this more than a loop over `step*.sh`, and each one would
break a naive version:

- **Every lab's last step deletes what the lab created.** Running it would
  leave exactly the empty namespace you started with, so teardown is skipped
  unless you ask for it.
- **Steps share shell state.** Lab 4's step 2 sets `API_IP` and defines
  `probe_api`, which step 3 calls; lab 10 passes `FALCO_NS` and `FALCO_POD`
  forward. The steps are therefore *sourced into one shell*, not run as
  separate processes.
- **Some steps are meant to fail.** A quota rejection, an admission denial and
  a blocked client all exit non-zero and are the point of their lab. A
  non-zero step is reported, never a reason to stop.
- **Labs 0 and 9 open a select menu and lab 10 needs a terminal.** The menus
  are answered from this VM's configuration, and the session is given a pty so
  `kubectl exec -it` works.

Two labs correctly produce no workloads however you run them: **lab 2** tests
every request with `--dry-run=server`, so nothing is ever persisted, and
**lab 6** is pure Docker with no cluster involvement. **Lab 7** creates only
cluster-scoped policy objects; its Pod requests are dry-runs too.

## Questions

`theory.md` is procedural: each lab states an objective and numbered steps, and
contains no questions at all. The cards in `questions/` add them.

```bash
bin/hk question 08     # what the lab asks, and the commands to run
bin/hk solution 08     # the answers, and what each command should show
```

`hk deploy lab08` prints both after deploying. Add `--no-solution` to print
only the questions and keep the exercise intact.

Both read local files, so they work with no VM running — you can read a lab's
questions before deciding to deploy it, or after destroying everything.

Deploying a lab also puts its question card in `~/labs/labNN/QUESTIONS.txt`.
The **solutions are never shipped into the VM**; they stay on the host behind
`hk solution`, for the same reason deploy stages a lab rather than solving it.

Each card carries the lab's objective, the theory needed to answer, three to
five questions, and a separate answer for each. Both cards also print **the
lab's own steps**. The question card lists them in order, as the procedure to
work through. The solution card places each one **directly under the answer it
evidences**, with what it should produce — so a question, its answer and the
commands that demonstrate it are read together. `solution_steps` in each card
holds that mapping; an answer that is pure reasoning says so instead.

Those commands are never copied into `questions/`. They are read from the
generated `LAB.md`, in the same order `extract-labs.py` turns `theory.md`'s
bash blocks into `stepNN.sh` — so "STEP 3 OF 5" on a card is always
`step03.sh` in the VM. `tests/test_cards.py` asserts that alignment for all
eleven labs, because a drift there would point a card at a different command
than the file it names while both still looked correct. They are hand-written, because
there is nothing in `theory.md` to extract them from — so editing `theory.md`
and re-running `bin/extract-labs.py` refreshes the kits but never the cards.
They live in `questions/` rather than beside the kits precisely because
`extract-labs.py` deletes that whole tree when it regenerates it.

The cards are parsed without PyYAML, which no stock macOS Python has. The cost
is that they must stay inside a small YAML subset — plain `key: value`, folded
`key: >-` blocks, and lists of `- >-` items. `tests/test_cards.py` pins that
grammar, checks the parser rejects anything else rather than mis-reading it,
and verifies every card answers every question it asks.

## Clearing up after a lab

Three levels, cheapest first:

1. `hk reset lab04` — deletes the lab's namespaces and cluster-scoped objects,
   recreates the namespaces empty, restores pristine files. Seconds. Use this
   between attempts at the same lab.
2. `hk remove lab04` — as above, but leaves nothing behind and marks the lab
   undeployed. Use this when you are done with it.
3. `hk restore` — rolls the whole VM back to the snapshot. Use this after
   breaking the cluster itself.

## Destroying

`hk destroy` means everything: both virtual machines, every lab in the lab VM,
and Rancher along with its CA and all its data. It does not ask, and it cannot
be undone.

```bash
bin/hk destroy           # both machines
bin/hk destroy labs      # the lab VM only
bin/hk destroy mgmt      # the management VM only  (= hk mgmt destroy)
```

`hk destroy labs` removes the lab cluster from Rancher first, while its agent
can still be reached, so no dead cluster is left in Cluster Management. `hk
destroy` on its own does not bother: the Rancher holding that record is being
deleted in the same breath.

Two things on your own machine outlive any of these, because both needed
`sudo` and one lives in the system keychain: the `/etc/hosts` entry and the
trusted lab CA. The hosts entry still applies to a rebuilt management VM. **The
CA does not** — a rebuilt `hk-mgmt` mints a new one under the same name, and
the stale root is exactly what makes a browser reject the new Rancher. `hk
destroy` prints the command to remove it.

## What each lab needs

Every capability is installed up front, so any lab can be deployed at any time.
The `needs` field in `labs.yml` records why each one is there:

| `needs` | Labs | Requirement |
| --- | --- | --- |
| `cluster` | 0, 1, 2, 3, 5, 7, 8 | plain k3s |
| `netpol` | 4 | a CNI that **enforces** NetworkPolicy, not just stores it |
| `docker` | 6 | builds local images; no cluster involved |
| `gvisor` | 9 | a real sandbox handler installed on the node |
| `falco` | 10 | a runtime sensor with a working alert path |

## Tests

```bash
tests/run.sh
```

Everything that can be checked without a virtual machine: 413 assertions,
about two seconds. It starts no VM, changes nothing on this Mac and touches no
cluster.

| Suite | Covers |
| --- | --- |
| `test_repo.sh` | shell and Python syntax, `vagrant validate`, all four playbooks parse, every role a playbook names exists, `labs.yml` is readable by each of the three parsers that read it, the two machines cannot share a name or address, every lab has a kit, and `extract-labs.py` still reproduces those kits from `theory.md` |
| `test_hk_cli.sh` | what each `hk` command *would* run |
| `test_browser_setup.py` | the `/etc/hosts` rewriting and superseded-CA detection behind `hk rancher --setup` |
| `test_cards.py` | the question cards, and the YAML subset parser that reads them without PyYAML |

`test_hk_cli.sh` is the interesting one. `tests/stub-bin` holds a fake
`vagrant` and `ansible-playbook` that record their arguments instead of doing
anything, and track which machines are notionally running so a build can reach
its Ansible half. Putting that directory first on `PATH` makes every dispatch
path testable — including `hk destroy`, which is the one command that must
never be tested for real. So there are assertions that `hk destroy labs` leaves
`hk-mgmt` alone, that `hk destroy labs` unimports first but a bare `hk destroy`
does not, and that `lab04`, `lab4`, `04` and `4` all reach the same lab.

The parts of `hk rancher --setup` that decide *what* to change are pure
functions, so they are tested directly — including against this Mac's own
`/etc/hosts`, checking every unrelated line survives and a second pass changes
nothing. The superseded-CA tests generate real CAs with `openssl` and confirm
that the CA in use is never among those marked for removal.

What these do not cover: anything that needs a running machine. A build, an
import, a Rancher login and the two `sudo` steps are proved by running them —
`hk build` fails loudly rather than reporting success it has not verified.

## Cluster DNS

Both clusters are pointed at a DNS upstream that was *proved* to answer, rather
than at whatever the node inherited. The `dnsupstream` role tries the node's
own nameservers in order, falls back to `1.1.1.1` and `8.8.8.8`, and fails the
build with a clear message if none of them answers.

This is not defensive decoration. CoreDNS forwards to the resolv.conf kubelet
hands its Pods, which under VirtualBox NAT is `10.0.2.3` — VirtualBox's DNS
proxy. On a host whose own resolvers are IPv6, that proxy answers over IPv6
only, and the dead IPv4 entry is the one an IPv4-only Pod network is left with.
Every in-cluster lookup of an external name then fails with SERVFAIL, a long
way from its cause: Falco's `falcoctl` init container crash-looping, or a
Rancher agent that never registers.

Override `hk_dns_fallbacks` if your network blocks public resolvers.

## Design notes

**k3s, not kubeadm.** It has an arm64 build, boots in under a minute, embeds
containerd, and its kube-router NetworkPolicy controller genuinely enforces —
unlike kind's default CNI, which would make Lab 4 pass for the wrong reason.
Traefik and servicelb are disabled; no lab uses them.

**gVisor, not Kata.** Kata needs nested virtualisation, which VirtualBox on
Apple Silicon does not expose to guests. gVisor's systrap platform needs none
and supports arm64. k3s does *not* auto-detect `runsc`, so the role writes a
`config.toml.tmpl` extending k3s's base template, detecting the containerd CRI
plugin key at runtime rather than hardcoding it.

**Configuration proves itself.** The gVisor role launches a real sandboxed Pod;
the Falco role triggers a shell and waits for the alert. A capability that
cannot work fails at configure time, not at study time.

**Falco's namespace is a deliberate exception.** It is labelled `privileged`,
not `restricted`, because the sensor is a privileged DaemonSet. That is the
documented exception pattern, scoped to one namespace.

**Rancher is a view, and an honest one.** An unimported lab cluster behaves
exactly as it did before the management VM existed. An imported one carries
Rancher's admission webhook, which gates namespace creation — so `hk import`
proves admission still works before returning, `hk deploy` retries through a
restarting webhook, and the README says what importing costs rather than
claiming it is free.

**Deploy stages, it does not solve.** Namespaces and files are created for you;
the lab's own commands are left for you to run. Automating those would delete
the exercise.

## Layout

```
labs.yml                  both VM specs, the Rancher pins, the lab catalogue
Vagrantfile               creates the two VMs only; declares no provisioner
bin/hk                    host-side wrapper for everything
bin/make-inventory        the seam: vagrant ssh-config -> Ansible inventory,
                          carrying its host-key and identity options
bin/extract-labs.py       regenerates lab kits from ../theory.md
ansible/site.yml          configure the lab VM: Docker, k3s, gVisor, Falco
ansible/lab.yml           deploy or remove one lab
ansible/mgmt.yml          configure the management VM: RKE2, then Rancher
ansible/import.yml        register the lab cluster with Rancher, or unregister
ansible/inventory/        generated — do not edit by hand
ansible/roles/            common, dnsupstream, docker, k3s, gvisor, falco,
                          labkit, rke2, rancher, rancherlink
bin/hk-browser-setup      gives this Mac hostname resolution and CA trust
bin/hk-ca                 the lab CA, kept on the host so it survives a rebuild
bin/hk-card               renders a lab's question or solution card
bin/hk-run                runs a deployed lab's own steps inside the VM
questions/labNN.yml       hand-written; theory.md has no questions to extract
tests/run.sh              every check that needs no VM
tests/stub-bin/           a fake vagrant, so `hk destroy` can be tested safely
ansible/roles/labkit/files/labNN/   generated — do not edit by hand
```

Edit `../theory.md`, re-run `bin/extract-labs.py`, then `bin/hk deploy lab04`
again to push the refreshed kit into the VM.

## Caveats

- The lab VM wants 6 GB of RAM and 4 vCPUs, since k3s, Falco and gVisor run
  together. The optional management VM wants another 10 GB and 4 vCPUs, so
  running both needs a host with 16 GB to spare. Build it only when you want
  the Rancher view; `hk mgmt stop` frees it again.
- Falco is always running, so its sensor logs contain activity from whatever
  lab you are working on. That is realistic, and Lab 10 depends on it.
- `hk reset` and `hk remove` do not touch the `study`, `study-net` and
  `study-policy` namespaces, which belong to the chapter examples rather than
  to any numbered lab.
