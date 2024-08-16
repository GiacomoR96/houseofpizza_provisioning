/*variable "AWS_ACCESS_KEY" {
  type = string
  default = ""
}
variable "AWS_SECRET_KEY" {
  type = string
  default = ""
}
variable "AWS_TOKEN" {
  type = string
  default = ""
}*/
variable "AWS_REGION" {
  default = "us-east-1"
}
variable "iam_access_entries" {
  type = list(object({
    policy_arn     = string
    principal_arn  = string
  }))

  default = [
    {
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      principal_arn = "arn:aws:iam::851725487849:user/UserProvisioning"   // TODO: Modify reference user here.
    }
  ]
}