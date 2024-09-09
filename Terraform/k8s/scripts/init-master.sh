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
