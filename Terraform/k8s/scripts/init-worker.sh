#!/bin/bash

echo "Init configuration worker"

exec &> /var/log/init-worker.log

set -o verbose
set -o errexit
set -o pipefail

export KUBEADM_TOKEN=${kubeadm_token}
export MASTER_IP=${master_ip}
export MASTER_PRIVATE_IP=${master_private_ip}
export KUBERNETES_VERSION="1.31.0"

# Set this only after setting the defaults
set -o nounset

# We to match the hostname expected by kubeadm an the hostname used by kubelet
LOCAL_IP_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
FULL_HOSTNAME="$(curl -s http://169.254.169.254/latest/meta-data/hostname)"

########################################
########################################
# Install containerd
########################################
########################################
echo "Init step - Install containerd"

sudo apt-get update
sudo apt-get install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install containerd.io

# Forwarding IPv4 and letting iptables see bridged traffic
cat << EOF | sudo tee /etc/modules-load.d/k8s.conf 
overlay 
br_netfilter 
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

sudo systemctl restart containerd
sudo systemctl enable containerd

echo "Finish step - Install containerd"

########################################
########################################
# Install Kubernetes components
########################################
########################################
echo "Init step - Install Kubernetes components"

sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm
sudo apt-mark hold kubelet kubeadm 
kubeadm completion bash > /etc/bash_completion.d/kubeadm

# Start services
systemctl enable kubelet
systemctl start kubelet

echo "Finish step - Install Kubernetes components"

########################################
########################################
# Initialize the Kube node
########################################
########################################

sudo bash <<EOF
rm /etc/containerd/config.toml
systemctl restart containerd
rm -rf /etc/cni/net.d
kubeadm reset --force
EOF

# TODO : Insert here kubeadm join cluster after resolve problem with calico/flannel/etc..

echo "Finish configuration worker"