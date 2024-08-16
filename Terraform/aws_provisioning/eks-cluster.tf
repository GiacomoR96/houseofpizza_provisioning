module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.23.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    master = {
      name = "node-group-master"

      instance_types = ["t2.medium"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }

    worker = {
      name = "node-group-worker"

      instance_types = ["t2.medium"]

      min_size     = 2
      max_size     = 6
      desired_size = 2
    }
  }
}

resource "aws_eks_access_entry" "eks_access_entry" {
  for_each       = { for entry in var.iam_access_entries : entry.principal_arn => entry }
  cluster_name  = local.cluster_name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  depends_on = [
    module.eks
  ]
}

resource "aws_eks_access_policy_association" "eks_policy_association" {
  for_each       = { for entry in var.iam_access_entries : entry.principal_arn => entry }
  cluster_name  = local.cluster_name
  policy_arn    = each.value.policy_arn
  principal_arn = each.value.principal_arn

  access_scope {
    type       = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.eks_access_entry
  ]
}