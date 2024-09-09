data "aws_availability_zones" "available" {}

resource "random_string" "suffix" {
  length  = 16
  special = false
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

data "cloudinit_config" "master" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "init-master.sh"
    content_type = "text/x-shellscript"

    content = templatefile("scripts/init-master.sh", {
    kubeadm_token = templatefile("token/token-format.tpl", { token1 = join("", random_shuffle.token1.result), token2 = join("", random_shuffle.token2.result) } ),
    ip_address    = aws_eip.master.public_ip,
    cluster_name  = var.cluster_name,
    aws_region    = var.AWS_REGION,
    aws_subnets   = join(" ", concat("${aws_subnet.public_subnet.*.id}", ["${aws_subnet.public_subnet[0].id}"]))
    })
  }

  depends_on = [
    random_shuffle.token1,
    random_shuffle.token2,
  ]
}

resource "aws_instance" "master" {
  ami                     = "ami-0e86e20dae9224db8"
  instance_type           = "t2.medium"
  vpc_security_group_ids  = [aws_security_group.kubernetes.id]
  key_name                = aws_key_pair.keypair.key_name
  subnet_id               = aws_subnet.public_subnet[0].id
  iam_instance_profile    = aws_iam_instance_profile.master_profile.name
  user_data               = data.cloudinit_config.master.rendered
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
      timeout     = "5m"
    }
  
    inline = [
      "sudo apt install python3 -y"
    ]
  }

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

data "cloudinit_config" "worker" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "init-worker.sh"
    content_type = "text/x-shellscript"

    content = templatefile("scripts/init-worker.sh", {
    kubeadm_token = templatefile("token/token-format.tpl", { token1 = join("", random_shuffle.token1.result), token2 = join("", random_shuffle.token2.result) } ),
    master_ip     = aws_eip.master.public_ip,
    master_private_ip = aws_instance.master.private_ip,
    })
  }

  depends_on = [
    random_shuffle.token1,
    random_shuffle.token2,
  ]
}

resource "aws_launch_template" "worker" {
  name = "${var.cluster_name}-worker"
  image_id = "ami-0e86e20dae9224db8"
  instance_type           = "t2.medium"
  key_name                = aws_key_pair.keypair.key_name
  user_data = data.cloudinit_config.worker.rendered

  iam_instance_profile {
    name = aws_iam_instance_profile.worker_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = ["${aws_security_group.kubernetes.id}"]
  }

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size = 10
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.cluster_name}-worker"
    }
  }
}

resource "aws_autoscaling_group" "worker" {
  desired_capacity   = 1
  max_size           = 4
  min_size           = 1
  vpc_zone_identifier = [aws_subnet.public_subnet[0].id]

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }
}

/* TODO: Use this configuration for master, worker and db
>hosts.ini;
	  [webserver]
    ${aws_instance.master.public_ip}
    ${aws_instance.worker[0].public_ip}
    ${aws_instance.worker[1].public_ip}
    [dbserve]
    ${aws_instance.dbserver.public_ip}
*/

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
aws_subnets: "${join(" ", concat("${aws_subnet.public_subnet.*.id}", ["${aws_subnet.public_subnet[0].id}"]))}"

aws_access_key: "${file("credential_key/aws_access_key")}"
aws_secret_access_key: "${file("credential_key/aws_secret_access_key")}"
 EOF

  // TODO: Add here reference for worker in future
  depends_on = [
    aws_instance.master,
  ]
}

// Ansible configuration for master node
resource "null_resource" "ansible_provisioner_master" {
  provisioner "local-exec" {
    //command = "ansible-playbook --private-key ${path.module}/.ssh/terraform.pem -i ${file("${path.module}/playbooks/hosts.ini")}, master.yml"
    command = "ansible-playbook --private-key ../.ssh/terraform.pem -i ${aws_instance.master.public_ip}, master.yml"
    working_dir = "${path.module}/playbooks"
  }

  depends_on = [
    local_file.inventory
  ]
}

/*
TODO : To improve ssh connection, use this with first tasks on all yml

    - name: Write the new ec2 instance host key to known hosts
      connection: local
      shell: "ssh-keyscan -H {{ lookup('ini', 'master', file='hosts.ini') }} >> ~/.ssh/known_hosts"

*/