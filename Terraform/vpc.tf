#####
# VPC
#####
resource "random_id" "randomness" {
  byte_length = 16
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  //enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  count               = "${length(var.aws_zones_elb)}"
  vpc_id              = aws_vpc.vpc.id
  cidr_block          = cidrsubnet(var.subnet_cidrs.public, 4, count.index)
  availability_zone   = "${var.aws_zones_elb[count.index]}"
  
  tags = {
    Name = "${var.cluster_name}-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "hybrid_subnet" {
  count               = "${length(var.aws_zones_ec2)}"
  vpc_id              = aws_vpc.vpc.id
  cidr_block          = cidrsubnet(var.subnet_cidrs.hybrid, 4, count.index)
  availability_zone   = "${var.aws_zones_ec2[count.index]}"
  
  tags = {
    Name = "${var.cluster_name}-hybrid-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count               = "${length(var.aws_zones_db)}"
  vpc_id              = aws_vpc.vpc.id
  cidr_block          = cidrsubnet(var.subnet_cidrs.private, 8, count.index)
  availability_zone   = "${var.aws_zones_db[count.index]}"
  
  tags = {
    Name = "${var.cluster_name}-private-subnet-${count.index}"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.cluster_name}-gw"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id = "${element(aws_subnet.public_subnet.*.id, 0)}"

  tags = {
    Name = "${var.cluster_name}-gw-nat"
  }

  depends_on = [aws_subnet.public_subnet, aws_internet_gateway.gw, aws_eip.nat]
}

############
## Routing (public subnets)
############

resource "aws_route_table" "route" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block  = "0.0.0.0/0"
    gateway_id  = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.cluster_name}-aws_route_table-route"
  }
}

resource "aws_route_table_association" "route_public" {
  count           = "${length(var.aws_zones_elb)}"
  subnet_id       = "${element(aws_subnet.public_subnet.*.id, count.index)}"
  route_table_id  = aws_route_table.route.id
}

resource "aws_route_table_association" "route_hybrid" {
  count           = "${length(var.aws_zones_ec2)}"
  subnet_id       = "${element(aws_subnet.hybrid_subnet.*.id, count.index)}"
  route_table_id  = aws_route_table.route.id
}

resource "aws_route_table_association" "route_private" {
  count           = "${length(var.aws_zones_db)}"
  subnet_id       = "${element(aws_subnet.private_subnet.*.id, count.index)}"
  route_table_id  = aws_route_table.route.id
}