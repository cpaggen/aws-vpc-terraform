provider "aws" {
  access_key = var.accessKey
  secret_key = var.secretKey
  region = "us-east-1"
}

resource "aws_vpc" "terraformvpc1" {
  cidr_block       = "10.10.0.0/16"
  instance_tenancy = "dedicated"

  tags = {
    Name = "terraform1"
  }
}

resource "aws_subnet" "first"{
  cidr_block = "10.10.1.0/24"
  vpc_id     = aws_vpc.terraformvpc1.id
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "second"{
  cidr_block = "10.10.2.0/24"
  vpc_id     = aws_vpc.terraformvpc1.id
  availability_zone = "us-east-1b"
}

resource "aws_route_table" "mgmt-rt" {
  vpc_id = aws_vpc.terraformvpc1.id
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.terraformvpc1.id

  tags = {
    Name = "internet"
  }
}

resource "aws_route" "mgmt-default" {
  route_table_id = aws_route_table.mgmt-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
  depends_on = [
    aws_route_table.mgmt-rt,
    aws_internet_gateway.igw
  ]
}

resource "aws_route_table_association" "inet-assoc1" {
  subnet_id = aws_subnet.first.id
  route_table_id = aws_route_table.mgmt-rt.id
}

resource "aws_route_table_association" "inet-assoc2" {
  subnet_id = aws_subnet.second.id
  route_table_id = aws_route_table.mgmt-rt.id
}

resource "aws_security_group" "cpaggen-sg" {
  vpc_id = aws_subnet.first.vpc_id
  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "ec2_instance_one" {
  associate_public_ip_address = true
  ami = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "virginia-keypair-one"
  vpc_security_group_ids = [aws_security_group.cpaggen-sg.id]
  subnet_id              = aws_subnet.first.id

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name = "cpaggen-one"
  }
}

resource "aws_instance" "ec2_instance_two" {
  associate_public_ip_address = true
  ami = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "virginia-keypair-one"
  vpc_security_group_ids = [aws_security_group.cpaggen-sg.id]
  subnet_id              = aws_subnet.second.id

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name = "cpaggen-two"
  }
}

output "vpc-id" {
    value = aws_vpc.terraformvpc1.id
}

output "ec1-public-ip" {
  value = aws_instance.ec2_instance_one.public_ip
}

output "ec2-public-ip" {
  value = aws_instance.ec2_instance_two.public_ip
}

