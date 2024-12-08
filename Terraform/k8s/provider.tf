provider "aws" {
  access_key  = "${file("credential_key/aws_access_key")}"
  secret_key  = "${file("credential_key/aws_secret_access_key")}"
  region      = var.AWS_REGION
}