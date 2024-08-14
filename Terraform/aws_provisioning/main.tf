data "aws_availability_zones" "available" {}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

locals {
  cluster_name = "eks-${random_string.suffix.result}"
}

#resource "null_resource" "this" {
#  provisioner "local-exec" {
#    command = "env"
#    environment = {
#      AWS_ACCESS_KEY_ID     = data.aws_credentials.default.access_key
#      AWS_SECRET_ACCESS_KEY = data.aws_credentials.default.secret_key
#      AWS_SECURITY_TOKEN    = data.aws_credentials.default.token
#      AWS_SESSION_TOKEN     = data.aws_credentials.default.token
#    }
#  }
#}


/*resource "null_resource" "this" {
  provisioner "local-exec" { 
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      exec "mkdir credential_key"
      exec "cd credential_key"
      exec "cat ~/.aws/credentials | grep 'aws_access_key_id' | cut -d '=' -f 2 > aws_access_key_id"
      exec "cat ~/.aws/credentials | grep 'aws_secret_access_key' | cut -d '=' -f 2 > aws_secret_access_key"
      exec "cat ~/.aws/credentials | grep 'aws_session_token' | cut -d '=' -f 2 > aws_session_token"
    EOT
  }
}*/

#variable "aws_access_key" {}
#variable "aws_secret_key" {}
#variable "aws_token" {}
