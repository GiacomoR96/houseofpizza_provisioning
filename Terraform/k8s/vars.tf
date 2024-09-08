variable "AWS_REGION" {
  default = "us-east-1"
}

variable "aws_zones" {
  type = list
  description = "AWS AZs (Availability zones) where subnets should be created"
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "ansible_user" {
  default = "ubuntu"
}

#####
# K8S variables
#####

variable "cluster_name" {
  description = "Name of the AWS Kubernetes cluster - will be used to name all created resources"
  default = "k8s-cluster"
}
