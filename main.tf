provider "aws" {
  region = var.region
}

#VPC DEPLOYMENT
resource "aws_vpc" "test_vpc" {
  cidr_block = "10.0.0.0/16"
}

#PUBLIC SUBNET
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.test_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

#PRIVATE SUBNET
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.test_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.test_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

#Filter to grab latest Amazon Linux AMI
data "aws_ami" "amazon-linux" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-2.0.20240223.0-x86_64-gp2"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#Create Main Security Group with Ports 22, 80, and 443 open for ingress traffic
resource "aws_security_group" "main_sg" {
  name        = "main_sg"
  description = "primary east sg"
  vpc_id      = aws_vpc.test_vpc.id

  ingress {
    description = "HTTPS inbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH inbound"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP inbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Create EIP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

#Create NAT Gateway for Private Subnet
resource "aws_nat_gateway" "nat_gw" {
  depends_on    = [aws_eip.nat]
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id
}

#Create IGW in Public Subnet
resource "aws_internet_gateway" "igw" {
  depends_on = [aws_vpc.test_vpc, aws_subnet.public_subnet]
  vpc_id     = aws_vpc.test_vpc.id
                                  
  #Get main route table to modify
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

#Associate Public Route Table with Public Subnets
resource "aws_route_table_association" "rt_associate_public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rt_associate_public2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.rt.id
}

#Create Private Route Table for Internal Traffic
resource "aws_route_table" "rt_private" {
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
}

#Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "rt_associate_private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.rt_private.id
}

#Create EC2 Instance with HTTPD Bootstrapped
resource "aws_instance" "webserver" {
  depends_on                  = [aws_nat_gateway.nat_gw]
  ami                         = data.aws_ami.amazon-linux.id
  subnet_id                   = aws_subnet.private_subnet.id
  instance_type               = "t2.micro"
  security_groups             = ["${aws_security_group.main_sg.id}"]
  associate_public_ip_address = false
  user_data                   = <<-EOF
        #!/bin/bash
        sudo yum update -y
        sudo yum install -y httpd
        echo "<h1>Webserver A</h1>" > /var/www/html/index.html
        sudo systemctl start httpd
        sudo systemctl enable httpd
        EOF

  tags = {
    Name = "webserver1"
  }
}

resource "aws_instance" "webserver2" {
  depends_on                  = [aws_nat_gateway.nat_gw]
  ami                         = data.aws_ami.amazon-linux.id
  subnet_id                   = aws_subnet.private_subnet.id
  instance_type               = "t2.micro"
  security_groups             = ["${aws_security_group.main_sg.id}"]
  associate_public_ip_address = false
  user_data                   = <<-EOF
        #!/bin/bash
        sudo yum update -y
        sudo yum install -y httpd
        echo "<h1>Webserver B</h1>" > /var/www/html/index.html
        sudo systemctl start httpd
        sudo systemctl enable httpd
        EOF

  tags = {
    Name = "webserver2"
  }
}

resource "aws_instance" "webserver3" {
  depends_on                  = [aws_nat_gateway.nat_gw]
  ami                         = data.aws_ami.amazon-linux.id
  subnet_id                   = aws_subnet.private_subnet.id
  instance_type               = "t2.micro"
  security_groups             = ["${aws_security_group.main_sg.id}"]
  associate_public_ip_address = false
  user_data                   = <<-EOF
        #!/bin/bash
        sudo yum update -y
        sudo yum install -y httpd
        echo "<h1>Webserver B</h1>" > /var/www/html/index.html
        sudo systemctl start httpd
        sudo systemctl enable httpd
        EOF

  tags = {
    Name = "webserver3"
  }
}

#Create Target Group for ALB
resource "aws_lb_target_group" "alb_tg" {
  name     = "tg-a"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.test_vpc.id
}

#Create ALB
 resource "aws_lb" "alb" {
  name               = "tf-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.main_sg.id}"]
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.public_subnet2.id]
}

#Create ALB Listener
resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

#Attach Target Group to ALB for Webserver1
resource "aws_lb_target_group_attachment" "alb_attach" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.webserver.id
  port             = 80
}

#Attach Target Group to ALB for Webserver2
resource "aws_lb_target_group_attachment" "alb_attach2" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.webserver2.id
  port             = 80
}

#Attach Target Group to ALB for Webserver3
resource "aws_lb_target_group_attachment" "alb_attach3" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.webserver3.id
  port             = 80
}

#Output Webserver Private IP and ALB DNS after script completes
output "Webserver-Private-IP" {
  value = aws_instance.webserver.private_ip
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}
