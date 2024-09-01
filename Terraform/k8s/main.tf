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
  ami                     = "ami-0a0e5d9c7acc336f1"
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
  image_id = "ami-0a0e5d9c7acc336f1"
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