# Container Escape Lab
 
A reproducible Vagrant lab for studying **the container boundary itself** — the
Linux kernel mechanisms that separate a container from its host, and the ways
those mechanisms are weakened, dissolved by misconfiguration, or bypassed by
defects at the runtime and kernel levels. Each exercise is reproducible and
resettable independently of the others.
 
Because the exercises deliberately span **incompatible** toolchains — an old
`runc` for one, a pre-patch **kernel with cgroup v1** for another — the lab is
split across **two target VMs**, divided along the one axis that cannot be
swapped on a running machine: the kernel. Userspace differences within a VM are
handled seamlessly by a per-exercise selector. See `LAB-VERSIONING.md` for the
full rationale.
 
## The two target VMs
 
| VM | Base | Serves | Why |
|---|---|---|---|
| `runtime` | Ubuntu 18.04 | 01 socket · 02 privileged · 03 CVE-2019-5736 | pinned **Docker 18.09.1 / runc 1.0-rc6** (vulnerable) |
| `kernel` | Ubuntu 20.04 | 04 CVE-2022-0492 · 05 capstone | pinned **kernel 5.4.0-90 + cgroup v1 + unprivileged userns** |
 
One old kernel serves both kernel exercises: CVE-2022-0492 needs a pre-5.4.177
kernel with cgroup v1, and the capstone (latent since 2017) is vulnerable on the
same kernel — so no third VM is required.
 
## One-command bring-up
 
Bring up only the VM you need:
 
```bash
# runtime exercises (01–03)
vagrant up runtime && vagrant ssh runtime
 
# kernel exercises (04–05) — provisions the pinned kernel, then reboots
vagrant up kernel  && vagrant ssh kernel
```
 
Inside a VM, select an exercise (validates the VM, pins any required version,
points you at the folder):
 
```bash
./select-exercise.sh 03
cd exercises/03-runc-cve-2019-5736
cat README.md          # objective, pinned versions, hints, mitigations
./setup.sh             # provision the scenario from the clean baseline
# ... work through the README ...
./teardown.sh          # return to the clean baseline
```
 
## One-command reset
 
```bash
# Per-exercise: undo what a single exercise created
./teardown.sh                         # inside the exercise directory
 
# Per-VM, guaranteed-clean: restore the clean-baseline snapshot
vagrant snapshot restore runtime clean-baseline
 
# Hard reset: rebuild a VM from scratch
vagrant destroy -f kernel && vagrant up kernel
```
 
## Layout
 
```
container-escape-lab/
├── Vagrantfile                 # defines both target VMs, ships exercises into each
├── provision-runtime.sh        # runtime VM: pinned Docker 18.09.1 / runc 1.0-rc6
├── provision-kernel.sh         # kernel VM: pinned kernel 5.4.0-90, cgroup v1, userns
├── select-exercise.sh          # per-exercise validation + version pinning inside a VM
├── LAB-VERSIONING.md           # version-management strategy and matrix
├── README.md                   # this file
└── exercises/
    ├── 01-docker-socket/            # the daemon socket == root on the host
    ├── 02-privileged_container/     # --privileged and the capability model
    ├── 03-runc-cve-2019-5736/       # runc /proc/self/exe overwrite (runtime defect)
    ├── 04-cgroups-cve-2022-0492/    # cgroup v1 release_agent (kernel defect via userns)
    └── 05-capstone-cve-2026-31431/  # algif_aead kernel LPE (the shared-kernel limit)
```
 
## Exercise contract
 
Every exercise directory is **self-contained** and holds:
 
| File | Purpose |
|---|---|
| `Dockerfile` / `docker-compose.yml` | defines the system under study |
| `setup.sh` | provisions the scenario from the clean baseline |
| `teardown.sh` | returns the environment to that clean baseline |
| `README.md` | objective, **pinned versions**, what to observe, mitigations |
 
For the two CVE exercises that reproduce a real, weaponisable escape (03 and the
capstone), the directory ships a vulnerable **target** and conceptual hints only;
the exploitation is left to the solver and is not distributed.
 
## Pinned toolchains
 
**`runtime` VM** (exercises 01–03):
 
| Component | Version | Note |
|---|---|---|
| Base box | `ubuntu/bionic64` (18.04) | |
| Docker CE | `18.09.1` (held) | vulnerable to CVE-2019-5736 |
| containerd.io | `1.2.2-3` | verify with `apt-cache madison` |
| runc | `1.0-rc6` (bundled) | the defect under study in Ex. 03 |
| cgroup | v1 (bionic default) | |
| Compose | v2 plugin (dropped in) | exercise compose files use the v2 schema |
 
**`kernel` VM** (exercises 04–05):
 
| Component | Version | Note |
|---|---|---|
| Base box | `ubuntu/focal64` (20.04) | |
| Kernel | `5.4.0-90-generic` (held) | pre-CVE-2022-0492 fix; also vulnerable to the capstone |
| cgroup | **v1** (forced: `systemd.unified_cgroup_hierarchy=0`) | required by Ex. 04 |
| Unpriv. userns | enabled | required by Ex. 04 |
| Docker CE | current | Docker is not the vulnerable component here |
 
Toolchain packages are `apt-mark hold`-pinned so they cannot drift between runs.
Exact apt version strings vary by mirror — confirm the pins once with
`apt-cache madison` / `apt-cache search` as described in `LAB-VERSIONING.md`.