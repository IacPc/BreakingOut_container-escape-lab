# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# container-escape-lab — Vagrantfile
# =============================================================================
# Two isolated target VMs, one per kernel regime (Chapter 4, §4.4.2):
#
#   runtime  (Ubuntu 18.04)  → exercises 01, 02, 03   [userspace runtime CVEs]
#   kernel   (Ubuntu 20.04)  → exercises 04, 05        [kernel-level CVEs]
#
# Per-exercise version selection happens INSIDE each VM with:
#     ./select-exercise.sh <NN>
#
# The two VMs exist because the kernel cannot be swapped seamlessly on a running
# machine, whereas Docker/runc (userspace) can. See select-exercise.sh.
#
# Bring up only what you need:
#     vagrant up runtime && vagrant ssh runtime
#     vagrant up kernel  && vagrant ssh kernel
# =============================================================================

Vagrant.configure("2") do |config|

  # --- Global isolation: host-only networking, no bridge to anything real ----
  # (Chapter 4, §4.5). No forwarded ports and no public/bridged NIC are defined.

  # =========================================================================
  # VM 1 — runtime target  (exercises 01, 02, 03)
  # =========================================================================
  config.vm.define "runtime", autostart: false do |rt|
    rt.vm.box      = "generic/ubuntu1804"      # Ubuntu 18.04 LTS
    rt.vm.hostname = "runtime-target"

    rt.vm.network "private_network", ip: "192.168.122.3"   # host-only, isolated

    rt.vm.provider "libvirt" do |lv|
      lv.uri    = "qemu:///system"
      lv.memory = 2048
      lv.cpus   = 2
    end

    # Provision the pinned-vulnerable Docker/runc stack + compose plugin.
    rt.vm.provision "shell", path: "provision-runtime.sh"

  end

  # =========================================================================
  # VM 2 — kernel target  (exercises 04, 05)
  # =========================================================================
  config.vm.define "kernel", autostart: false do |kt|
    kt.vm.box      = "generic/ubuntu2004"       # Ubuntu 20.04 LTS
    kt.vm.hostname = "kernel-target"

    kt.vm.network "private_network", ip: "192.168.122.20"

    kt.vm.provider "libvirt" do |lv|
      lv.uri    = "qemu:///system"
      lv.memory = 2048
      lv.cpus   = 2
    end

    # Provision the pinned vulnerable kernel + cgroup v1 + unprivileged userns.
    # NOTE: this changes the boot kernel and GRUB cmdline, so a reboot is
    # required. The provisioner requests it; if your Vagrant does not reboot
    # automatically, run:  vagrant reload kernel
    kt.vm.provision "shell", path: "provision-kernel.sh", reboot: true
 end

  config.vm.synced_folder ".", "/vagrant",
    type: "rsync",
    rsync__exclude: [".git/", ".vagrant/"],
    rsync__verbose: true
    

end
###############

   