#!/usr/bin/env bash
# install.sh: Prepares a Ubuntu LTS node for running Kubernetes.
#
# This script installs and configures all necessary dependencies for a
# Kubernetes node, including containerd, runc, CNI plugins, and the
# Kubernetes toolchain (kubeadm, kubelet, kubectl).
#
# It can set up a worker node by default, or a control-plane node if
# the --control-plane flag is provided.
#
# USAGE:
#   For a worker node:
#     curl -sSL https://raw.githubusercontent.com/felix-kaestner/kubeadm-install/main/install.sh | sudo bash -s
#
#   For a control-plane node:
#     curl -sSL https://raw.githubusercontent.com/felix-kaestner/kubeadm-install/main/install.sh | sudo bash -s -- --control-plane
#
# NOTE: This script must be run with root privileges (e.g., using sudo).

set -euo pipefail

CONTAINERD_VERSION=""
RUNC_VERSION=""
CNI_PLUGINS_VERSION=""
K8S_VERSION=""

ARCH=$(dpkg --print-architecture)

IS_CONTROL_PLANE=false

info() {
    echo "[INFO]  " "$@"
}

success() {
    echo "[SUCCESS] " "$@"
}

fatal() {
    echo "[FATAL] " "$@" >&2
    exit 1
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        fatal "This script must be run as root. Please use 'sudo'."
    fi
}

get_latest_version() {
    local repo="$1"
    local url="https://api.github.com/repos/${repo}/releases/latest"
    local version

    version=$(curl -sSL "$url" | grep '"tag_name":' | sed -e 's/v//' | cut -d'"' -f4)
    if [[ -z "$version" ]]; then
        fatal "Could not fetch the latest version for ${repo}. Please check repository name or network connection."
    fi

    echo "$version"
}

get_latest_k8s_version() {
    local version

    version=$(curl -L -s https://dl.k8s.io/release/stable.txt | sed -e 's/v//' | cut -d'.' -f1-2)
    if [[ -z "$version" ]]; then
        fatal "Could not fetch the latest stable Kubernetes version. Please check network connection."
    fi

    echo "$version"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --control-plane)
            IS_CONTROL_PLANE=true
            shift
            ;;
        --containerd-version)
            CONTAINERD_VERSION="${2#v}"
            shift 2
            ;;
        --runc-version)
            RUNC_VERSION="${2#v}"
            shift 2
            ;;
        --cni-plugins-version)
            CNI_PLUGINS_VERSION="${2#v}"
            shift 2
            ;;
        --k8s-version)
            K8S_VERSION="${2#v}"
            shift 2
            ;;
        --help | -h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --control-plane              Set up a control-plane node (default is worker node)"
            echo "  --containerd-version <ver>   Specify containerd version (default: latest)"
            echo "  --runc-version <ver>         Specify runc version (default: latest)"
            echo "  --cni-plugins-version <ver>  Specify CNI plugins version (default: latest)"
            echo "  --k8s-version <ver>          Specify Kubernetes version (default: latest stable)"
            exit 0
            ;;
        *)
            fatal "Unknown option: $1"
            ;;
        esac
    done
}

install_containerd() {
    info "Step 1: Downloading and installing containerd v${CONTAINERD_VERSION}..."
    local url="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz"
    curl -sSLO "${url}"
    curl -sSL "${url}.sha256sum" | sha256sum -c
    tar -C /usr/local -xzf "containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz"
    success "containerd installed."
}

install_runc() {
    info "Step 2: Downloading and installing runc v${RUNC_VERSION}..."
    local url="https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc"
    curl -sSLO "${url}.${ARCH}"
    curl -sSL "${url}.sha256sum" | grep "runc.${ARCH}" | sha256sum -c
    install -m 755 "runc.${ARCH}" /usr/local/sbin/runc
    success "runc installed."
}

install_cni_plugins() {
    info "Step 3: Downloading and installing CNI plugins v${CNI_PLUGINS_VERSION}..."
    local url="https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz"
    curl -sSLO "${url}"
    curl -sSL "${url}.sha256" | sha256sum -c
    mkdir -p /opt/cni/bin
    tar -C /opt/cni/bin -xzf "cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz"
    success "CNI plugins installed."
}

setup_containerd_service() {
    info "Step 4: Setting up containerd.service for systemd..."
    local url="https://raw.githubusercontent.com/containerd/containerd/main/containerd.service"
    curl -sSL "${url}" -o /etc/systemd/system/containerd.service
    systemctl daemon-reload
    systemctl enable --now containerd
    success "containerd.service configured and started."
}

configure_kernel_modules() {
    info "Step 5: Enabling kernel modules (overlay, br_netfilter)..."
    cat <<EOF | tee /etc/modules-load.d/containerd.conf >/dev/null
overlay
br_netfilter
EOF
    modprobe overlay
    modprobe br_netfilter
    success "Kernel modules enabled."
}

configure_sysctl() {
    info "Step 6: Configuring required sysctl parameters for Kubernetes networking..."
    mkdir -p /etc/sysctl.d
    cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
    sysctl --system
    success "Sysctl parameters applied."
}

install_k8s() {
    info "Step 6: Installing cri-tools, kubeadm, kubelet, and kubectl for K8s v${K8S_VERSION}..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    apt-get update
    apt-get install -y cri-tools
    cat <<EOF | tee /etc/crictl.yaml >/dev/null
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
    success "cri-tools installed and crictl configured."

    apt-get install -y kubernetes-cni
    rm -f /etc/cni/net.d/*.conf*

    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    systemctl enable --now kubelet
    success "kubeadm, kubelet, and kubectl installed and marked."
}

configure_containerd_cgroup() {
    info "Step 7: Configuring containerd to use SystemdCgroup..."
    local version
    local sandbox

    sandbox=$(kubeadm config images list | grep pause | sort -r | head -n1)

    mkdir -p /etc/containerd
    containerd config default >/etc/containerd/config.toml

    version=$(awk -F ' = ' '/^version =/ {print $2; exit}' /etc/containerd/config.toml)
    case $version in
    2)
        sed -i \
            -e "s#sandbox_image = .*#sandbox_image = '${sandbox}'#" \
            -e 's/SystemdCgroup = false/SystemdCgroup = true/' \
            /etc/containerd/config.toml
        ;;
    3)
        sed -i \
            -e "s#sandbox = .*#sandbox = '${sandbox}'#" \
            -e 's/^\(\s*\)ShimCgroup = ''.*/&\n\1SystemdCgroup = true/' \
            /etc/containerd/config.toml
        ;;
    *)
        fatal "Unsupported containerd config version: ${version}."
        ;;
    esac

    if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
        fatal "Failed to enable SystemdCgroup in containerd config."
    fi

    systemctl restart containerd
    success "containerd configured for SystemdCgroup and restarted."
}

initialize_control_plane() {
    info "Step 8: Initializing Kubernetes control plane with kubeadm..."
    export KUBECONFIG=/etc/kubernetes/admin.conf

    systemctl stop kubelet
    kubeadm config images list
    kubeadm config images pull --cri-socket=unix:///run/containerd/containerd.sock
    systemctl start kubelet

    cat <<EOF >kubeadm-config.yaml
kind: InitConfiguration
apiVersion: kubeadm.k8s.io/v1beta4
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta4
networking:
  podSubnet: "192.168.0.0/16"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
EOF

    kubeadm init --config kubeadm-config.yaml

    kubectl taint nodes --all node-role.kubernetes.io/control-plane-

    mkdir -p "${HOME:-/root}/.kube"
    cp -f $KUBECONFIG "${HOME:-/root}/.kube/config"

    echo
    echo "----------------------------------------------------------------"
    echo "Your Kubernetes control-plane has been initialized successfully!"
    echo
    echo "Now, deploy a Pod network. For example Calico:"
    echo "  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml"
    echo
    echo "Then, join worker nodes by running the 'kubeadm join' command provided above on each node as root."
    echo "----------------------------------------------------------------"
}

main() {
    check_root

    if [[ ${1:-} == "--" ]]; then
        shift
    fi

    parse_args "$@"

    if [[ -z "$CONTAINERD_VERSION" ]]; then CONTAINERD_VERSION=$(get_latest_version "containerd/containerd"); fi
    if [[ -z "$RUNC_VERSION" ]]; then RUNC_VERSION=$(get_latest_version "opencontainers/runc"); fi
    if [[ -z "$CNI_PLUGINS_VERSION" ]]; then CNI_PLUGINS_VERSION=$(get_latest_version "containernetworking/plugins"); fi
    if [[ -z "$K8S_VERSION" ]]; then K8S_VERSION=$(get_latest_k8s_version); fi

    info "Using the following component versions:"
    echo "  - containerd:      v${CONTAINERD_VERSION}"
    echo "  - runc:            v${RUNC_VERSION}"
    echo "  - cni-plugins:     v${CNI_PLUGINS_VERSION}"
    echo "  - kubernetes:      v${K8S_VERSION}"

    install_containerd
    install_runc
    install_cni_plugins
    setup_containerd_service

    configure_kernel_modules
    configure_sysctl

    install_k8s

    configure_containerd_cgroup

    if [[ "${IS_CONTROL_PLANE}" == true ]]; then
        initialize_control_plane
    else
        success "Worker node setup complete."
        info "To join this node to a cluster, run the 'kubeadm join' command provided by the control plane."
    fi
}

main "$@"
