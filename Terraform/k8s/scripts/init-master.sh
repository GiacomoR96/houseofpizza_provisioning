#!/bin/bash

echo "Init configuration master"

exec &> /var/log/init-master.log

set -o verbose
set -o errexit
set -o pipefail

export HOME="/home/ubuntu"
export KUBEADM_TOKEN=${kubeadm_token}
export IP_ADDRESS=${ip_address}
export CLUSTER_NAME=${cluster_name}
export AWS_REGION=${aws_region}
export AWS_SUBNETS="${aws_subnets}"
export KUBERNETES_VERSION="1.31.0"

# Set this only after setting the defaults
set -o nounset

# We needed to match the hostname expected by kubeadm an the hostname used by kubelet
LOCAL_IP_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
FULL_HOSTNAME="$(curl -s http://169.254.169.254/latest/meta-data/hostname)"


########################################
########################################
# Install AWS CLI client
########################################
########################################
echo "Init step - Install AWS CLI client"

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip -y 
unzip awscliv2.zip > /dev/null
sudo ./aws/install

echo "Finish step - Install AWS CLI client"

########################################
########################################
# Tag subnets
########################################
########################################
echo "Init step - Tag subnets"

for SUBNET in $AWS_SUBNETS
do
  aws ec2 create-tags --resources $SUBNET --tags Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared --region $AWS_REGION
done

echo "Finish step - Tag subnets"


########################################
########################################
# Install containerd
########################################
########################################

sudo swapoff -a

# Enable kernel modules and configure sysctl
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

sudo sysctl --system

# Install container runtime


# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates curl gpg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
 
# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update


# Install and configure containerd
sudo apt-get install containerd.io
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
systemctl status containerd

# Enable IP Forwarding and apply changes
sudo sh -c "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf"
sudo sysctl -p


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
sudo bash <<EOF
kubeadm completion bash > /etc/bash_completion.d/kubeadm
EOF

#kubectl completion bash > /etc/bash_completion.d/kubectl

curl -LO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Start services
sudo systemctl enable kubelet
sudo systemctl start kubelet

echo "Finish step - Install Kubernetes components"

########################################
########################################
# Initialize the Kube cluster
########################################
########################################
echo "Init step - Initialize the Kube cluster"

sudo bash <<EOF
rm /etc/containerd/config.toml
systemctl restart containerd
kubeadm reset --force
rm -rf /etc/cni/net.d
kubeadm init
EOF


mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown $(id -u):$(id -g) /home/ubuntu/.kube/config

echo "Finish step - Initialize the Kube cluster"

########################################
########################################
# Configuration Kubernetes networking
########################################
########################################
echo "Init step - Configuration Kubernetes networking"

#Calico configuration
echo "First part - calico"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.4/manifests/tigera-operator.yaml

echo "Second part - calico"
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.4/manifests/custom-resources.yaml

cat >/home/ubuntu/custom-resources.yaml <<EOF
---
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  # Configures Calico networking.
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.0.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
---
EOF

kubectl create -f /home/ubuntu/custom-resources.yaml

echo "Finish - calico"

#Flannel configuration
#kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml


# Allow the user to administer the cluster
#kubectl create clusterrolebinding admin-cluster-binding --clusterrole=cluster-admin --user=admin

echo "Finish step - Configuration Kubernetes networking"



echo "Finish configuration master"
#echo kubeadm token create --print-join-command