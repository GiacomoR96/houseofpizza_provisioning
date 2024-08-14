provider "aws" {
  access_key  = "${file("credential_key/aws_access_key")}"
  secret_key  = "${file("credential_key/aws_secret_access_key")}"
  #token      = "${var.aws_token}"
  region      = var.AWS_REGION
}
provider "kubernetes" {
  host                    = module.eks.cluster_endpoint
  cluster_ca_certificate  = base64decode(module.eks.cluster_certificate_authority_data)
}