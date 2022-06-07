provider "aws" {
  region = "eu-central-1"
  # credentials come from ~/.aws/credentials (AWS CLI)
}

resource "aws_s3_bucket" "bucket1" {
  bucket = "cpaggen-bucket-one"
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aesbucket1" {
  bucket = aws_s3_bucket.bucket1.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#locking part

resource "aws_dynamodb_table" "tf_remote_state_locking" {
  hash_key = "LockID"
  name     = "cpaggen-tfstate"
  attribute {
    name = "LockID"
    type = "S"
  }
  billing_mode = "PAY_PER_REQUEST"
}

terraform {
  backend "s3" {
    bucket         = "cpaggen-terraform-state"
    key            = "index"
    dynamodb_table = "cpaggen-tfstate"
    region         = "eu-central-1"
  }
}

resource "aws_vpc" "terraformvpc1" {
  cidr_block       = "10.10.0.0/16"
  instance_tenancy = "dedicated"

  tags = {
    Name = "terraform1"
  }
}

resource "aws_subnet" "first" {
  cidr_block        = "10.10.1.0/24"
  vpc_id            = aws_vpc.terraformvpc1.id
  availability_zone = "eu-central-1a"
}

resource "aws_subnet" "second" {
  cidr_block        = "10.10.2.0/24"
  vpc_id            = aws_vpc.terraformvpc1.id
  availability_zone = "eu-central-1b"
}

resource "aws_route_table" "mgmt-rt" {
  vpc_id = aws_vpc.terraformvpc1.id
  tags = {
    Name = "cpaggen-rt"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.terraformvpc1.id

  tags = {
    Name = "cpaggen-internet"
  }
}

resource "aws_route" "mgmt-default" {
  route_table_id         = aws_route_table.mgmt-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
  depends_on = [
    aws_route_table.mgmt-rt,
    aws_internet_gateway.igw
  ]
}

resource "aws_main_route_table_association" "main-rt" {
  vpc_id         = aws_vpc.terraformvpc1.id
  route_table_id = aws_route_table.mgmt-rt.id
}

#resource "aws_route_table_association" "inet-assoc1" {
#  subnet_id = aws_subnet.first.id
#  route_table_id = aws_route_table.mgmt-rt.id
#}
#
#resource "aws_route_table_association" "inet-assoc2" {
#  subnet_id = aws_subnet.second.id
#  route_table_id = aws_route_table.mgmt-rt.id
#}

locals {
  rulesmap = {
    "HTTP" = {
      port        = 80,
      cidr_blocks = ["0.0.0.0/0"],
    }
    "SSH" = {
      port        = 22,
      cidr_blocks = ["0.0.0.0/0"],
    },
    "BLASTR" = {
      port        = 8888,
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

resource "aws_security_group" "cpaggen-sg" {
  vpc_id = aws_subnet.first.vpc_id

  dynamic "ingress" {
    for_each = local.rulesmap
    content {
      description = ingress.key # HTTP or SSH
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cpaggen-default"
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
  ami                         = "ami-02584c1c9d05efa69" // data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = "frankfurt-keypair-one"
  vpc_security_group_ids      = [aws_security_group.cpaggen-sg.id]
  subnet_id                   = aws_subnet.first.id
  connection {
    agent       = false
    host        = self.public_ip
    private_key = file("frankfurt-keypair-one.pem")
    type        = "ssh"
    user        = "ubuntu"
  }

  provisioner "file" {
    source      = "nginx-playbook.yaml"
    destination = "/home/ubuntu/nginx-playbook.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -",
      "sudo apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main\"",
      "sudo apt-get update -y && sudo apt-get install terraform -y",
      "sudo apt install software-properties-common -y",
      "sudo add-apt-repository ppa:deadsnakes/ppa -y",
      "sudo apt install python3.7 python3-venv python3.7-venv python3-pip -y",
      "python3.7 -m venv py37-venv",
      "source ./py37-venv/bin/activate",
      "pip3 install --upgrade pip",
      "pip3 install blastradius graphviz",
      "/home/ubuntu/.local/bin/blast-radius --serve --port 8888 &"
    ]
  }
  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "cpaggen-one"
  }
}

resource "aws_instance" "ec2_instance_two" {
  associate_public_ip_address = true
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = "frankfurt-keypair-one"
  vpc_security_group_ids      = [aws_security_group.cpaggen-sg.id]
  subnet_id                   = aws_subnet.second.id
  connection {
    agent       = false
    host        = self.public_ip
    private_key = file("frankfurt-keypair-one.pem")
    type        = "ssh"
    user        = "ec2-user"
  }

  provisioner "file" {
    source      = "nginx-playbook.yaml"
    destination = "/home/ec2-user/nginx-playbook.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sleep 10",
      # "sudo yum install -y amazon-linux-extras",
      # "sudo amazon-linux-extras install ansible2 -y",
      # "sleep 5",
      # "ansible-playbook /home/ec2-user/nginx-playbook.yaml"
    ]


  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "cpaggen-two"
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

output "bucket-name_b1" {
  value = aws_s3_bucket.bucket1.bucket
}
