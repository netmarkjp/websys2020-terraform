# PreRequirements:
# - Create KeyPair
# - Install terraform, and run `terraform init`
#
# Example:
# ```sh
# terraform apply -var "rds_master_user_password=foo"
# ```

# Syntax: https://www.terraform.io/docs/configuration/index.html
variable key_name {
  type    = string
  default = "websys2020"
}

variable rds_master_user_password {
  type    = string
  default = "0d986a1e36e91662de6186e66030a6e5e470039e"
}

provider "aws" {
  profile = "default"
  region  = "ap-northeast-1"
  # access_key = "" # set profile. or use env AWS_ACCESS_KEY_ID
  # secret_key = "" # set profile. or use env AWS_SECRET_ACCESS_KEY
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_security_groups" "default" {
  filter {
    name   = "group-name"
    values = ["default"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  aws_security_group_default_id = data.aws_security_groups.default.ids[0]
}

resource "aws_security_group_rule" "allow_from_uec" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["130.153.0.0/16"]
  security_group_id = local.aws_security_group_default_id
  description       = "SSH from UEC"
}

## EC2
data "aws_kms_alias" "ebs" {
  name = "alias/aws/ebs"
}
resource "aws_instance" "websys2020" {
  # https://www.terraform.io/docs/providers/aws/r/instance.html
  ami                    = "ami-0f310fced6141e627"
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [local.aws_security_group_default_id]
  root_block_device {
    delete_on_termination = true
    volume_size           = 8
    volume_type           = "gp2"
    encrypted             = true
    kms_key_id            = data.aws_kms_alias.ebs.target_key_arn
  }
}

## RDS
resource "aws_db_instance" "websys2020" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.17"
  instance_class         = "db.t2.micro"
  username               = "admin"
  password               = var.rds_master_user_password
  identifier             = "db-instance-1"
  vpc_security_group_ids = [local.aws_security_group_default_id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

## ELB
resource "aws_security_group" "websys2020_lb" {
  name        = "websys2020_lb"
  description = "ELB SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    description = "Allow HTTP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "websys2020" {
  name               = "websys2020"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.websys2020_lb.id]
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
}

resource "aws_lb_target_group" "websys2020" {
  name     = "websys2020"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
}

resource "aws_lb_target_group_attachment" "websys2020" {
  target_group_arn = aws_lb_target_group.websys2020.arn
  target_id        = aws_instance.websys2020.id
  port             = 80
}

resource "aws_lb_listener" "websys2020" {
  load_balancer_arn = aws_lb.websys2020.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websys2020.arn
  }
}

# Allow from ELB SG to Default SG
resource "aws_security_group_rule" "allow_from_elb" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = aws_security_group.websys2020_lb.id
  security_group_id        = local.aws_security_group_default_id
  description              = "HTTP from ELB"
}
