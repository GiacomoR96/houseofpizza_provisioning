#####
# Security group
#####

resource "aws_security_group" "kubernetes" {
  name        = "${var.cluster_name}-sg"
  vpc_id      = "${aws_vpc.vpc.id}"
  description = "Open ports 22, 8080, 443 and 6443"

  #Allow incoming TCP requests on port 22 from any IP
  # TODO : Modify cidr_blocks
  ingress {
    description = "Incoming SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Allow incoming TCP requests on port 8080 from any IP
  ingress {
    description = "Incoming 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Allow incoming TCP requests on port 443 from any IP
  ingress {
    description = "Incoming 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Allow API connections only from specific CIDR
  # TODO : Modify cidr_blocks
  ingress {
    description = "Incoming 6443"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  /*ingress {
    description = "Allow the security group members to talk with each other without restrictions"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    //source_security_group_id = aws_security_group.kubernetes.id
  }*/

  tags = {
    Name = "${var.cluster_name}-sg"
  }

}