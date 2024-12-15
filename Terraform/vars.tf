variable "AWS_REGION" {
  default = "us-east-1"
}

variable "subnet_cidrs" {
  default = {
    public  = "10.0.0.0/20"   # Subnet for Load Balancer (ELB)
    hybrid  = "10.0.16.0/20"  # Subnet for instances EC2
    private = "10.0.32.0/20"  # Subnet for database (DB)
  }
}

variable "aws_zones_elb" {
  type = list
  default = ["us-east-1a", "us-east-1d"]
}

variable "aws_zones_ec2" {
  type = list
  default = ["us-east-1c"]
}

variable "aws_zones_db" {
  type = list
  default = ["us-east-1b"]
}

variable "ansible_user" {
  default = "ubuntu"
}

#####
# K3S variables
#####

variable "cluster_name" {
  description = "Name of the AWS Kubernetes cluster - will be used to name all created resources"
  default = "k3s-cluster"
}
