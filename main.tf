provider "aws" {
  region = "eu-west-1"
}


# VPC
resource "aws_vpc" "main_vpc" {
  cidr_block       					= var.vpc_cidr
  instance_tenancy 					= var.instance_tenancy
  enable_dns_hostnames             	= var.enable_dns_hostnames
  enable_dns_support              	= var.enable_dns_support
  tags = {
    Name = "Test_VPC"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "Test_IGW"
  }
}

resource "aws_subnet" "public" {
  count = length(var.subnets_cidr_public)
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = element(var.subnets_cidr_public,count.index)
  availability_zone = element(var.azs,count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "Subnet-Public${count.index+1}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.subnets_cidr_private)
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = element(var.subnets_cidr_private,count.index)
  availability_zone = element(var.azs,count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "Subnet-Private${count.index+1}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }
  tags = {
    Name = "Public_rt"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.main_nat.id
  }
  
   route {
    cidr_block = "192.168.0.0/16"
    gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  
   route {
    cidr_block = "172.16.0.0/12"
    gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  
   route {
    cidr_block = "10.0.0.0/8"
    gateway_id = aws_ec2_transit_gateway.main_tgw.id
  }
  
  tags = {
    Name = "Private_rt"
  }
}  

resource "aws_route_table_association" "a" {
  count = length(var.subnets_cidr_public)
  subnet_id      = element(aws_subnet.public.*.id,count.index)
  route_table_id = aws_route_table.public_rt.id
}

  
resource "aws_route_table_association" "b" {
  count = length(var.subnets_cidr_private)
  subnet_id      = element(aws_subnet.private.*.id,count.index)
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_eip" "nat" {
  vpc              = true
}


data "aws_subnet" "selected" {
  filter {
    name   = "tag:Name"
    values = ["Subnet-Public1"]
  }
  depends_on = [aws_subnet.public]
}

resource "aws_nat_gateway" "main_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = data.aws_subnet.selected.id

  tags = {
    Name = "Test_NGW"
  }

  depends_on = [aws_internet_gateway.main_igw]
}

resource "aws_ec2_transit_gateway" "main_tgw" {
  description = "TGW"
  auto_accept_shared_attachments = "enable"
}

data "aws_subnet_ids" "private" {
  vpc_id = aws_vpc.main_vpc.id
  filter {
    name   = "tag:Name"
    values = ["Subnet-Private*"] # insert values here
  }
}
  


resource "aws_ec2_transit_gateway_vpc_attachment" "example" {
  subnet_ids         = flatten([data.aws_subnet_ids.private])
  transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  vpc_id             = aws_vpc.main_vpc.id
  appliance_mode_support = "enable"
}


resource "aws_customer_gateway" "oakbrook" {
  bgp_asn    = 65000
  ip_address = "207.223.34.132"
  type       = "ipsec.1"

  tags = {
    Name = "Test_Oakbrook_CGW"
  }
}

resource "aws_customer_gateway" "miami" {
  bgp_asn    = 65000
  ip_address = "66.165.187.241"
  type       = "ipsec.1"

  tags = {
    Name = "Test_Miami_CGW"
  }
}

resource "aws_vpn_connection" "Oakbrook" {
  transit_gateway_id  = aws_ec2_transit_gateway.main_tgw.id
  customer_gateway_id = aws_customer_gateway.oakbrook.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = {
    Name = "Oakbrook_ipsec"
  }
  
}

resource "aws_vpn_connection" "Miami" {
  transit_gateway_id  = aws_ec2_transit_gateway.main_tgw.id
  customer_gateway_id = aws_customer_gateway.miami.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = {
    Name = "Miami_ipsec"
  }
}

resource "aws_security_group" "private_sg" {
  name        = "private_sg"
  description = "Private SG"
  vpc_id      = aws_vpc.main_vpc.id

  dynamic "ingress" {
    for_each = var.rules_inbound_private_sg
    content {
      from_port = ingress.value["port"]
      to_port = ingress.value["port"]
      protocol = ingress.value["proto"]
      cidr_blocks = ingress.value["cidr_block"]
    }
  }
  dynamic "egress" {
    for_each = var.rules_outbound_private_sg
    content {
      from_port = egress.value["port"]
      to_port = egress.value["port"]
      protocol = egress.value["proto"]
      cidr_blocks = egress.value["cidr_block"]
    }
  }
  tags = {
    Name = "test_private_sg"
  }
}

resource "aws_security_group" "public_sg" {
  name        = "public_sg"
  description = "public SG"
  vpc_id      = aws_vpc.main_vpc.id

  dynamic "ingress" {
    for_each = var.rules_inbound_public_sg
    content {
      from_port = ingress.value["port"]
      to_port = ingress.value["port"]
      protocol = ingress.value["proto"]
      cidr_blocks = ingress.value["cidr_block"]
    }
  }
  dynamic "egress" {
    for_each = var.rules_outbound_public_sg
    content {
      from_port = egress.value["port"]
      to_port = egress.value["port"]
      protocol = egress.value["proto"]
      cidr_blocks = egress.value["cidr_block"]
    }
  }
  tags = {
    Name = "test_public_sg"
  }
}
