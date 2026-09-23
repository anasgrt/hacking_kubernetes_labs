# Hacking Kubernetes — lab infrastructure

One virtual machine, built once, carrying every capability the labs need.
Labs are deployed into it one at a time and removed when you are finished.
The lab content comes from `../theory.md`, which this directory never modifies.

## How it works

Vagrant and Ansible stay separate tools with separate jobs — the `Vagrantfile`
declares no provisioner. `hk build` runs both in sequence so you only type one
command.

| Step | Tool | What it does | Command |
| --- | --- | --- | --- |
| 1 | Vagrant | Creates a bare Ubuntu VM. Nothing installed. | `hk build` |
| 2 | Ansible | Installs Docker, k3s, gVisor and Falco into it. | (same command) |
| Then | Ansible | Deploys one lab into the configured VM. | `hk deploy lab01` |

`hk configure` re-runs step 2 on its own when you want it.

The seam between Vagrant and Ansible is `bin/make-inventory`, which reads
`vagrant ssh-config` and writes an Ansible inventory. Because of it you can
rebuild the box without re-running Ansible, and re-run Ansible as often as you
like without touching the box.

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

### 2. Build the VM

```bash
cd labs-infra
bin/hk build
```

One command, two steps. First Vagrant clones the base box, boots it, and
attaches a host-only NIC at `192.168.56.110` — about a minute. Then
`bin/make-inventory` reads `vagrant ssh-config` and Ansible runs
`ansible/site.yml` over SSH:

1. Base packages and the Docker engine; pre-pulls the pinned
   `python:3.13-slim` digest.
2. k3s — waits for the node and CoreDNS, creates the `study*` namespaces the
   chapter examples use, side-loads the study image into containerd.
3. gVisor — installs `runsc`, wires it into k3s's containerd, creates the
   `gvisor` RuntimeClass, then **launches a real sandboxed Pod to prove it**.
4. Falco — installs the sensor on the modern eBPF driver, then **triggers a
   real shell and waits for the alert** before declaring success.
5. Runs `hk-lab check` and fails if any capability is unmet.

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
# the VM
bin/hk build             # create it and configure it  (Vagrant, then Ansible)
bin/hk configure         # re-run the Ansible half only
bin/hk check             # re-check its capabilities
bin/hk ssh               # shell into it
bin/hk snapshot          # save a restore point
bin/hk restore           # roll back to it
bin/hk stop              # shut down, keep the disk
bin/hk destroy           # delete it

# labs, inside the VM
bin/hk list              # every lab and whether it is deployed
bin/hk deploy lab04      # add a lab
bin/hk status lab04      # what it has created so far
bin/hk reset lab04       # clear what it created, keep it deployed
bin/hk remove lab04      # take it out entirely
```

A lab may be written `lab04`, `lab4`, `04` or `4`. `bin/hk` alone prints this.

## Clearing up after a lab

Three levels, cheapest first:

1. `hk reset lab04` — deletes the lab's namespaces and cluster-scoped objects,
   recreates the namespaces empty, restores pristine files. Seconds. Use this
   between attempts at the same lab.
2. `hk remove lab04` — as above, but leaves nothing behind and marks the lab
   undeployed. Use this when you are done with it.
3. `hk restore` — rolls the whole VM back to the snapshot. Use this after
   breaking the cluster itself.

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

**Deploy stages, it does not solve.** Namespaces and files are created for you;
the lab's own commands are left for you to run. Automating those would delete
the exercise.

## Layout

```
labs.yml                  the VM spec and the lab catalogue
Vagrantfile               creates the VM only; declares no provisioner
bin/hk                    host-side wrapper for everything
bin/make-inventory        the seam: vagrant ssh-config -> Ansible inventory,
                          carrying its host-key and identity options
bin/extract-labs.py       regenerates lab kits from ../theory.md
ansible/site.yml          configure the VM: Docker, k3s, gVisor, Falco
ansible/lab.yml           deploy or remove one lab
ansible/inventory/        generated — do not edit by hand
ansible/roles/            common, docker, k3s, gvisor, falco, labkit
ansible/roles/labkit/files/labNN/   generated — do not edit by hand
```

Edit `../theory.md`, re-run `bin/extract-labs.py`, then `bin/hk deploy lab04`
again to push the refreshed kit into the VM.

## Caveats

- The VM wants 6 GB of RAM and 4 vCPUs, since k3s, Falco and gVisor run
  together.
- Falco is always running, so its sensor logs contain activity from whatever
  lab you are working on. That is realistic, and Lab 10 depends on it.
- `hk reset` and `hk remove` do not touch the `study`, `study-net` and
  `study-policy` namespaces, which belong to the chapter examples rather than
  to any numbered lab.
