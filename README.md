<!--
# SPDX-FileCopyrightText: 2025 Felix Kästner
# SPDX-License-Identifier: Apache-2.0
-->

# kubeadm-install

This script automates the process of preparing a fresh Ubuntu LTS machine to be a Kubernetes node.

[![Issues](https://img.shields.io/github/issues/felix-kaestner/kubeadm-install?color=29b6f6&style=flat-square)](https://github.com/felix-kaestner/kubeadm-install/issues)
[![License](https://img.shields.io/github/license/felix-kaestner/kubeadm-install?color=29b6f6&style=flat-square)](https://github.com/felix-kaestner/kubeadm-install/blob/main/LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](https://github.com/felix-kaestner/kubeadm-install/pulls)

## Features

- **Fully Automated**: Installs and configures all required software from official sources.
- **Smart Versioning**: Automatically fetches the latest stable versions of Kubernetes, containerd, runc, and CNI plugins.
- **Flexible**: Allows you to override component versions with command-line flags.
- **Role-Aware**: Can set up a standard worker node or initialize a control-plane node.
- **Best Practices**:
  - Configures `containerd` with the required `SystemdCgroup` driver.
  - Enables required kernel modules (`overlay`, `br_netfilter`) and `sysctl` settings.
  - Uses the official Kubernetes `apt` repository and holds package versions to prevent unintended upgrades.
- **User-Friendly**: Provides clear, color-coded output to track progress and results.

## Prerequisites

- A fresh installation of **Ubuntu LTS** (e.g., 24.04).
- Root or `sudo` access on the machine.
- Internet connectivity to download components from GitHub and `pkgs.k8s.io`.

## Usage

The script is meant to be piped directly into `bash`.

**Important:** The `--` is used to separate `bash` options from the script's arguments. Always include it when passing flags to the script.

### 1. Set Up a Worker Node (Default)

This command uses the latest stable versions for all components.

```bash
curl -sSL https://raw.githubusercontent.com/felix-kaestner/kubeadm-install/main/install.sh | sudo bash -s
```

### 2. Set Up a Control-Plane Node

Use the `--control-plane` flag to install all dependencies and then initialize the cluster with `kubeadm init`.

```bash
curl -sSL https://raw.githubusercontent.com/felix-kaestner/kubeadm-install/main/install.sh | sudo bash -s -- --control-plane
```

The script will output the `kubeadm join` command for your worker nodes.

### 3. Pinning Specific Versions (Advanced)

You can override the automatically detected versions for specific needs.

```bash
curl -sSL https://raw.githubusercontent.com/felix-kaestner/kubeadm-install/main/install.sh | sudo bash -s -- --k8s-version 1.33 --containerd-version 2.1.3
```

Available override flags:

- `--k8s-version <version>` (e.g., `1.33`)
- `--containerd-version <version>` (e.g., `2.1.3`)
- `--runc-version <version>` (e.g., `1.3.0`)
- `--cni-plugins-version <version>` (e.g., `1.7.1`)

---

Released under the [Apache 2.0 License](LICENSE).
