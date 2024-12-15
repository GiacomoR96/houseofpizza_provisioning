data "aws_availability_zones" "available" {}

resource "random_id" "randomness" {
  byte_length = 16
}

resource "random_shuffle" "token1" {
  input        = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "a", "b", "c", "d", "e", "f", "g", "h", "i", "t", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
  result_count = 6
}

resource "random_shuffle" "token2" {
  input        = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "a", "b", "c", "d", "e", "f", "g", "h", "i", "t", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
  result_count = 16
}

##########
# Keypair
##########

resource "aws_key_pair" "keypair" {
  key_name   = var.cluster_name
  public_key = file(".ssh/terraform.pub")
}

#####
# S3 configuration
#####

resource "aws_s3_bucket" "jenkins-artifacts" {
  bucket = "jenkins-artifacts-${random_id.randomness.hex}"

  tags = {
    Name = "jenkins_artifacts"
  }
}

// See this for pipeline
// https://medium.com/@haroldfinch01/how-to-build-a-ci-cd-pipeline-for-terraform-infrastructure-3e7cab9fcdf7

#####
# Database configuration
#####

// TODO : Change subnet with private_subnet
resource "aws_instance" "database" {
  ami                     = "ami-0e86e20dae9224db8"
  instance_type           = "t2.medium"
  vpc_security_group_ids  = [aws_security_group.kubernetes.id]
  key_name                = aws_key_pair.keypair.key_name
  subnet_id               = aws_subnet.hybrid_subnet[0].id
  associate_public_ip_address = true

  tags = {
    Name = "database-instance"
  }

}

resource "null_resource" "database_transfer_folder" {
  count = "${length(aws_instance.database.*.id)}"

  provisioner "file" {
    source      = "${path.module}/database"
    destination = "/home/ubuntu/database"

    connection {
      type        = "ssh"
      host        = "${element(aws_instance.database.*.public_ip, count.index)}"
      user        = "ubuntu"
      private_key = file(".ssh/terraform.pem")
    }
  }

  depends_on = [
    aws_instance.database
  ]

}

// Ansible configuration for database node
resource "null_resource" "ansible_provisioner_database" {
  count = "${length(aws_instance.database.*.id)}"

  provisioner "local-exec" {
    command = "ansible-playbook --private-key ../.ssh/terraform.pem -i ${element(aws_instance.database.*.public_ip, count.index)}, database.yml"
    working_dir = "${path.module}/playbooks"
  }

  depends_on = [
    null_resource.database_transfer_folder
  ]

}

#####
# Master configuration
#####

resource "aws_iam_policy" "master_policy" {
  name        = "${var.cluster_name}-master"
  path        = "/"
  description = "Policy for role ${var.cluster_name}-master"
  policy      = "${file("policy/master-policy.json.tpl")}"
}

resource "aws_iam_role" "master_role" {
  name = "${var.cluster_name}-master"
  assume_role_policy = "${file("policy/sts-assumeRole.json")}"
}

resource "aws_iam_policy_attachment" "master-attach" {
  name = "master-attachment"
  roles = [aws_iam_role.master_role.name]
  policy_arn = aws_iam_policy.master_policy.arn
}

resource "aws_iam_instance_profile" "master_profile" {
  name = "${var.cluster_name}-master"
  role = aws_iam_role.master_role.name
}

resource "aws_eip" "master" {
  domain = "vpc"
}

resource "aws_instance" "master" {
  ami                     = "ami-0e86e20dae9224db8"
  instance_type           = "t2.medium"
  vpc_security_group_ids  = [aws_security_group.kubernetes.id]
  key_name                = aws_key_pair.keypair.key_name
  subnet_id               = aws_subnet.hybrid_subnet[0].id
  iam_instance_profile    = aws_iam_instance_profile.master_profile.name
  associate_public_ip_address = true

  tags = {
    Name = "master-instance"
  }

  provisioner "remote-exec" {
    # Establishes connection to be used by all
    # generic remote provisioners (i.e. file/remote-exec)
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(".ssh/terraform.pem")
      host        = self.public_ip
      timeout     = "1m"
    }
  
    inline = [
      "sudo apt install python3 -y"
    ]
  }

  depends_on = [
    aws_instance.database
  ]

}

#####
# Worker configuration
#####

resource "aws_iam_policy" "worker_policy" {
  name        = "${var.cluster_name}-worker"
  path        = "/"
  description = "Policy for role ${var.cluster_name}-worker"
  policy      = "${file("policy/worker-policy.json.tpl")}"
}

resource "aws_iam_role" "worker_role" {
  name                = "${var.cluster_name}-worker"
  assume_role_policy  = "${file("policy/sts-assumeRole.json")}"
}

resource "aws_iam_policy_attachment" "worker-attach" {
  name        = "worker-attachment"
  roles       = [aws_iam_role.worker_role.name]
  policy_arn  = aws_iam_policy.worker_policy.arn
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.cluster_name}-worker"
  role = aws_iam_role.worker_role.name
}

resource "aws_instance" "worker" {
  count = 2  # Change this for using multiple instances of worker.

  ami                    = "ami-0e86e20dae9224db8"
  instance_type          = "t2.medium"
  key_name               = aws_key_pair.keypair.key_name
  subnet_id              = aws_subnet.hybrid_subnet[0].id
  iam_instance_profile   = aws_iam_instance_profile.worker_profile.name
  associate_public_ip_address = true
  vpc_security_group_ids  = [aws_security_group.kubernetes.id]

  tags = {
    Name = "${var.cluster_name}-worker-${count.index}"
  }
}

// Generate inventory file
resource "local_file" "inventory" {
 filename = "${path.module}/playbooks/config_vars.yml"
 content = <<EOF
---
# ./config_vars.yml

master: "${aws_instance.master.public_ip}"
kubeadm_token: "${templatefile("token/token-format.tpl", { token1 = join("", random_shuffle.token1.result), token2 = join("", random_shuffle.token2.result) } )}"
ip_address: "${aws_eip.master.public_ip}"
cluster_name: "${var.cluster_name}"
aws_region: "${var.AWS_REGION}"
aws_subnets: "${join(" ", concat("${aws_subnet.hybrid_subnet.*.id}", ["${aws_subnet.hybrid_subnet[0].id}"]))}"

aws_access_key: "${file("credential_key/aws_access_key")}"
aws_secret_access_key: "${file("credential_key/aws_secret_access_key")}"
 EOF

  depends_on = [
    aws_instance.master
  ]
}

resource "null_resource" "worker_transfer_folder" {
  count = "${length(aws_instance.worker.*.id)}"

  provisioner "file" {
    source      = "${path.module}/.ssh"
    destination = "/home/ubuntu/ssh_keys"

    connection {
      type        = "ssh"
      host        = "${element(aws_instance.worker.*.public_ip, count.index)}"
      user        = "ubuntu"
      private_key = file(".ssh/terraform.pem")
    }
  }

  depends_on = [
    local_file.inventory
  ]

}

// Ansible configuration for master node
resource "null_resource" "ansible_provisioner_master" {
  provisioner "local-exec" {
    command = "ansible-playbook --private-key ../.ssh/terraform.pem -i ${aws_instance.master.public_ip}, master.yml"
    working_dir = "${path.module}/playbooks"
  }

  depends_on = [
    null_resource.worker_transfer_folder
  ]

}

// Ansible configuration for worker node
resource "null_resource" "ansible_provisioner_worker" {
  count = "${length(aws_instance.worker.*.id)}"

  provisioner "local-exec" {
    command = "ansible-playbook --private-key ../.ssh/terraform.pem -i ${element(aws_instance.worker.*.public_ip, count.index)}, worker.yml"
    working_dir = "${path.module}/playbooks"
  }

  depends_on = [
    null_resource.ansible_provisioner_master
  ]

}
