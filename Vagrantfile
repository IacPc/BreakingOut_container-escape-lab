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
    rt.vm.box      = "ubuntu/bionic64"      # Ubuntu 18.04 LTS
    rt.vm.hostname = "runtime-target"

    rt.vm.network "private_network", type: "dhcp"   # host-only, isolated

    rt.vm.provider "virtualbox" do |vb|
      vb.name   = "cel-runtime-target"
      vb.memory = 2048
      vb.cpus   = 2
    end

    # Provision the pinned-vulnerable Docker/runc stack + compose plugin.
    rt.vm.provision "shell", path: "provision-runtime.sh"

    # Ship the per-exercise selector and the exercises into the VM.
    rt.vm.provision "file", source: "select-exercise.sh", destination: "/home/vagrant/select-exercise.sh"
    rt.vm.provision "file", source: "exercises",          destination: "/home/vagrant/exercises"
    rt.vm.provision "shell", inline: "chmod +x /home/vagrant/select-exercise.sh /home/vagrant/exercises/*/*.sh || true"
  end

  # =========================================================================
  # VM 2 — kernel target  (exercises 04, 05)
  # =========================================================================
  config.vm.define "kernel", autostart: false do |kt|
    kt.vm.box      = "ubuntu/focal64"       # Ubuntu 20.04 LTS
    kt.vm.hostname = "kernel-target"

    kt.vm.network "private_network", type: "dhcp"   # host-only, isolated

    kt.vm.provider "virtualbox" do |vb|
      vb.name   = "cel-kernel-target"
      vb.memory = 2048
      vb.cpus   = 2
    end

    # Provision the pinned vulnerable kernel + cgroup v1 + unprivileged userns.
    # NOTE: this changes the boot kernel and GRUB cmdline, so a reboot is
    # required. The provisioner requests it; if your Vagrant does not reboot
    # automatically, run:  vagrant reload kernel
    kt.vm.provision "shell", path: "provision-kernel.sh", reboot: true

    kt.vm.provision "file", source: "select-exercise.sh", destination: "/home/vagrant/select-exercise.sh"
    kt.vm.provision "file", source: "exercises",          destination: "/home/vagrant/exercises"
    kt.vm.provision "shell", inline: "chmod +x /home/vagrant/select-exercise.sh /home/vagrant/exercises/*/*.sh || true"
  end

  config.vm.synced_folder ".", "/vagrant",
    type: "rsync",
    rsync__exclude: [".git/", ".vagrant/"],
    rsync__verbose: true
    

end
###############

   