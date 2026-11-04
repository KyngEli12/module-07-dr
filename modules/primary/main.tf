# ============================================================
# PRIMARY MODULE — us-east-1
# Full production stack: VPC, ALB, EC2 (Auto Scaling), RDS
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------
resource "aws_vpc" "primary" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.app_name}-primary-vpc"
    Environment = var.environment
    Region      = "primary"
  }
}

resource "aws_internet_gateway" "primary" {
  vpc_id = aws_vpc.primary.id

  tags = {
    Name = "${var.app_name}-primary-igw"
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.primary.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-primary-public-${count.index + 1}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.primary.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.app_name}-primary-private-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.primary.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary.id
  }

  tags = { Name = "${var.app_name}-primary-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway for private subnets
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.app_name}-primary-nat-eip" }
}

resource "aws_nat_gateway" "primary" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.app_name}-primary-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.primary.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.primary.id
  }

  tags = { Name = "${var.app_name}-primary-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-primary-alb-sg"
  description = "Allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.primary.id

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
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-primary-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.app_name}-primary-app-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = aws_vpc.primary.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-primary-app-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.app_name}-primary-rds-sg"
  description = "Allow MySQL from app tier only"
  vpc_id      = aws_vpc.primary.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-primary-rds-sg" }
}

# ------------------------------------------------------------
# Application Load Balancer
# ------------------------------------------------------------
resource "aws_lb" "primary" {
  name               = "${var.app_name}-primary-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name        = "${var.app_name}-primary-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "primary" {
  name     = "${var.app_name}-primary-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.primary.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
  }

  tags = { Name = "${var.app_name}-primary-tg" }
}

resource "aws_lb_listener" "primary" {
  load_balancer_arn = aws_lb.primary.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.primary.arn
  }
}

# ------------------------------------------------------------
# Launch Template + Auto Scaling Group
# ------------------------------------------------------------
resource "aws_launch_template" "primary" {
  name_prefix   = "${var.app_name}-primary-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3

    # Minimal health-check HTTP server for the lab
    cat > /opt/app.py << 'PYEOF'
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import json, socket

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/health':
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({
                    "status": "healthy",
                    "region": "us-east-1",
                    "host": socket.gethostname()
                }).encode())
            else:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'Primary region app — us-east-1')
        def log_message(self, *args):
            pass

    HTTPServer(('', 8080), Handler).serve_forever()
    PYEOF

    python3 /opt/app.py &
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.app_name}-primary-app"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "primary" {
  name                = "${var.app_name}-primary-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.primary.arn]
  health_check_type   = "ELB"

  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.primary.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.app_name}-primary-app"
    propagate_at_launch = true
  }
}

# ------------------------------------------------------------
# RDS — Primary (Multi-AZ for HA within primary region)
# ------------------------------------------------------------
resource "aws_db_subnet_group" "primary" {
  name       = "${var.app_name}-primary-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.app_name}-primary-db-subnet" }
}

resource "aws_db_instance" "primary" {
  identifier              = "${var.app_name}-primary-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.primary.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = true             # HA within primary region
  backup_retention_period = 7                # 7-day backups — required for read replica
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:05:00-sun:06:00"
  skip_final_snapshot     = true             # set false in production
  deletion_protection     = false            # set true in production
  storage_encrypted       = true

  tags = {
    Name        = "${var.app_name}-primary-db"
    Environment = var.environment
    DR          = "source"
  }
}
