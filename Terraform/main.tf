#Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

## SECURITY GROUP
#Create security group 
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins_sg"
  description = "Open ports 22, 8080, and 443"

  #Allow incoming TCP requests on port 22 from any IP
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

  #Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins_sg"
  }

}


### BUCKET S3
#Create random number for S3 bucket name
resource "random_id" "randomness" {
  byte_length = 16
}

#Create S3 bucket for Jenkins artifacts
resource "aws_s3_bucket" "jenkins-artifacts" {
  bucket = "jenkins-artifacts-${random_id.randomness.hex}"

  tags = {
    Name = "jenkins_artifacts"
  }
}

# Resource to avoid error "AccessControlListNotSupported: The bucket does not allow ACLs"
#resource "aws_s3_bucket_ownership_controls" "s3_bucket_acl_ownership" {
#  bucket = aws_s3_bucket.jenkins-artifacts.id
#  rule {
#    object_ownership = "ObjectWriter"
#  }
#}

#Make S3 bucket private
#resource "aws_s3_bucket_acl" "private_bucket" {
#  bucket = aws_s3_bucket.jenkins-artifacts.id
#  #acl    = "private"
#  depends_on = [aws_s3_bucket_ownership_controls.s3_bucket_acl_ownership]
#}

resource "aws_key_pair" "key_pair" {
  key_name   = var.KEY_NAME
  public_key = file("ssh_key/key_pair.pub")
}

## EC2 INSTANCE
#Create EC2 Instance
resource "aws_instance" "instance1" {
  ami                     = "ami-0a0e5d9c7acc336f1"
  instance_type           = "t2.medium"
  vpc_security_group_ids  = [aws_security_group.jenkins_sg.id]
  #key_name               = file("labsuser.pem")
  key_name                = var.KEY_NAME
  tags = {
    Name = "jenkins_instance"
  }
  
  #provisioner "local-exec" {
  #  interpreter=["/bin/bash", "-c"]
  #  command = "sudo apt-get update -y"
  #}

  provisioner "remote-exec" {
    # Establishes connection to be used by all
    # generic remote provisioners (i.e. file/remote-exec)
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("ssh_key/key_pair")
      host        = self.public_ip
      timeout     = "5m"
    }
  
    inline = [
      "sudo apt-get update -y",
      "sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key",
      "echo 'deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]' https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install jenkins -y",
      "sudo apt-get install openjdk-11-jdk -y",
      "sudo systemctl enable jenkins",
      "sudo systemctl start jenkins"
    ]
  }

}
