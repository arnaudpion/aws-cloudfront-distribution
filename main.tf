# VPC
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.100.0.0/16"

  tags = {
    Name = "${var.prefix}app-vpc"
  }
}

# Subnets : 2 apps (Private), 2 lb (Public)
resource "aws_subnet" "app_subnet_a" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.100.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-app-subnet-a"
  }
}

resource "aws_subnet" "app_subnet_b" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.100.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-app-subnet-b"
  }
}

resource "aws_subnet" "lb_subnet_a" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.100.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-lb-subnet-a"
  }
}

resource "aws_subnet" "lb_subnet_b" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.100.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-lb-subnet-b"
  }
}

# Gateways : IGW and NATGW
resource "aws_internet_gateway" "app_vpc_igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-igw"
  }
}

resource "aws_eip" "natgw_eip" {
  # vpc = true

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-natgw-eip"
  }
}

resource "aws_nat_gateway" "app_vpc_natgw" {
  allocation_id = aws_eip.natgw_eip.id
  subnet_id     = aws_subnet.lb_subnet_a.id

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-natgw"
  }

  depends_on = [aws_internet_gateway.app_vpc_igw]
}

# Route Tables and Associations to Subnets
resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.app_vpc_natgw.id
  }

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-app-rt"
  }
}

resource "aws_route_table_association" "app_subnet_a_rt_asso" {
  subnet_id      = aws_subnet.app_subnet_a.id
  route_table_id = aws_route_table.app_rt.id
}

resource "aws_route_table_association" "app_subnet_b_rt_asso" {
  subnet_id      = aws_subnet.app_subnet_b.id
  route_table_id = aws_route_table.app_rt.id
}

resource "aws_route_table" "lb_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_vpc_igw.id
  }

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-lb-rt"
  }
}

resource "aws_route_table_association" "lb_subnet_a_rt_asso" {
  subnet_id      = aws_subnet.lb_subnet_a.id
  route_table_id = aws_route_table.lb_rt.id
}

resource "aws_route_table_association" "lb_subnet_b_rt_asso" {
  subnet_id      = aws_subnet.lb_subnet_b.id
  route_table_id = aws_route_table.lb_rt.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  name        = "${var.prefix}alb-sg"
  description = "Allow HTTP and HTTPS"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}alb-sg"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.prefix}app-sg"
  description = "Allow HTTP from ALB and SSH from Bastion Host"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}app-sg"
  }
}

# Key pair
resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "kp-file" {
  content  = tls_private_key.rsa.private_key_pem
  filename = "${var.prefix}kp"
}

resource "aws_key_pair" "kp" {
  key_name   = "${var.prefix}kp"
  public_key = tls_private_key.rsa.public_key_openssh
  tags = {
  }
}

# App (web) servers
resource "aws_instance" "app_vm_a" {
  ami                         = data.aws_ami.amzn_linux_2023_latest.id
  instance_type               = "t3.nano"
  key_name                    = aws_key_pair.kp.key_name
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  subnet_id                   = aws_subnet.app_subnet_a.id
  associate_public_ip_address = false
  private_ip                  = "10.100.1.5"
  user_data                   = file("user_data.sh")

  tags = {
    Name = "${var.prefix}app-vm-a"
  }
  depends_on = [aws_nat_gateway.app_vpc_natgw]
}

resource "aws_instance" "app_vm_b" {
  ami                         = data.aws_ami.amzn_linux_2023_latest.id
  instance_type               = "t3.nano"
  key_name                    = aws_key_pair.kp.key_name
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  subnet_id                   = aws_subnet.app_subnet_b.id
  associate_public_ip_address = false
  private_ip                  = "10.100.2.5"
  user_data                   = file("user_data.sh")

  tags = {
    Name = "${var.prefix}app-vm-b"
  }
  depends_on = [aws_nat_gateway.app_vpc_natgw]
}

# ALB
resource "aws_lb" "alb" {
  name               = "${var.prefix}app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.lb_subnet_a.id, aws_subnet.lb_subnet_b.id]

  tags = {
    Name = "${var.prefix}app-alb"
  }
}

resource "aws_lb_target_group" "alb_tg" {
  name     = "${var.prefix}alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.app_vpc.id

  tags = {
    Name = "${lookup(aws_vpc.app_vpc.tags, "Name")}-alb-tg"
  }
}

resource "aws_lb_target_group_attachment" "app-vm-a-attachment" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.app_vm_a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "app-vm-b-attachment" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.app_vm_b.id
  port             = 80
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

# Additional "Bastion Host" in public subnet
resource "aws_security_group" "bastion_sg" {
  name        = "${var.prefix}bastion-sg"
  description = "Allow SSH from Everywhere" # Edit the cidr_blocks field to only allow your own IP address
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # cidr_blocks = [local.my_ip_address]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}bastion-sg"
  }
}

resource "aws_instance" "bastion_vm" {
  ami                         = data.aws_ami.amzn_linux_2023_latest.id
  instance_type               = "t2.nano"
  key_name                    = aws_key_pair.kp.key_name
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  subnet_id                   = aws_subnet.lb_subnet_a.id
  associate_public_ip_address = true
  private_ip                  = "10.100.3.5"
  user_data                   = file("user_data.sh")

  tags = {
    Name = "${var.prefix}bastion-vm"
  }
  depends_on = [aws_nat_gateway.app_vpc_natgw]
}