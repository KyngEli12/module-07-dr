# ============================================================
# DR MODULE — us-west-2  (Pilot Light)
#
# Pilot Light strategy:
#   - RDS read replica: ALWAYS RUNNING (data is warm)
#   - EC2 / ASG: STOPPED (instance exists, ami baked, starts on failover)
#   - ALB: running but healthy check passes only after EC2 starts
#
# Failover procedure (manual or automated via Lambda):
#   1. Promote RDS read replica → standalone primary
#   2. Update app config env var DB_HOST to DR endpoint
#   3. Set ASG desired_capacity = 1  (starts stopped instance)
#   4. Route 53 health check on primary fails → DR record goes live
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

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
# VPC (mirrors primary CIDR in a different range)
# ------------------------------------------------------------
resource "aws_vpc" "dr" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name   = "${var.app_name}-dr-vpc"
    Region = "dr"
  }
}

resource "aws_internet_gateway" "dr" {
  vpc_id = aws_vpc.dr.id
  tags   = { Name = "${var.app_name}-dr-igw" }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.app_name}-dr-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.app_name}-dr-private-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dr.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr.id
  }

  tags = { Name = "${var.app_name}-dr-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.app_name}-dr-nat-eip" }
}

resource "aws_nat_gateway" "dr" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.app_name}-dr-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.dr.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dr.id
  }

  tags = { Name = "${var.app_name}-dr-private-rt" }
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
  name        = "${var.app_name}-dr-alb-sg"
  description = "DR ALB - allow HTTP from internet"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-dr-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.app_name}-dr-app-sg"
  description = "DR app tier - allow from ALB only"
  vpc_id      = aws_vpc.dr.id

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

  tags = { Name = "${var.app_name}-dr-app-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.app_name}-dr-rds-sg"
  description = "DR RDS read replica - allow from app tier"
  vpc_id      = aws_vpc.dr.id

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

  tags = { Name = "${var.app_name}-dr-rds-sg" }
}

# ------------------------------------------------------------
# ALB (DR) — stays up, routes to stopped instance during standby
# ------------------------------------------------------------
resource "aws_lb" "dr" {
  name               = "${var.app_name}-dr-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name   = "${var.app_name}-dr-alb"
    Role   = "pilot-light"
  }
}

resource "aws_lb_target_group" "dr" {
  name     = "${var.app_name}-dr-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.dr.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30   # less frequent — DR is standby
  }

  tags = { Name = "${var.app_name}-dr-tg" }
}

resource "aws_lb_listener" "dr" {
  load_balancer_arn = aws_lb.dr.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dr.arn
  }
}

# ------------------------------------------------------------
# Launch Template — identical AMI to primary
# Instance starts STOPPED via ASG desired_capacity = 0
# ------------------------------------------------------------
resource "aws_launch_template" "dr" {
  name_prefix   = "${var.app_name}-dr-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3

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
                    "region": "us-west-2",
                    "mode": "DR_ACTIVE",
                    "host": socket.gethostname()
                }).encode())
            else:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'DR region app ACTIVE — us-west-2')
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
      Name = "${var.app_name}-dr-app"
      Role = "pilot-light"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Pilot Light: ASG exists but desired = 0 (no running instances until failover)
resource "aws_autoscaling_group" "dr" {
  name                = "${var.app_name}-dr-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.dr.arn]
  health_check_type   = "ELB"

  min_size         = 0
  max_size         = 2
  desired_capacity = 0   # KEY: pilot light — scale to 1 on failover

  launch_template {
    id      = aws_launch_template.dr.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.app_name}-dr-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "pilot-light"
    propagate_at_launch = true
  }
}

# ------------------------------------------------------------
# RDS Read Replica — cross-region (ALWAYS RUNNING)
# Data continuously replicated from primary. On failover: promote.
# ------------------------------------------------------------
resource "aws_db_subnet_group" "dr" {
  name       = "${var.app_name}-dr-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.app_name}-dr-db-subnet" }
}

resource "aws_db_instance" "dr_replica" {
  identifier              = "${var.app_name}-dr-replica"
  replicate_source_db     = var.primary_db_arn   # cross-region replication
  instance_class          = var.db_instance_class
  db_subnet_group_name    = aws_db_subnet_group.dr.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  skip_final_snapshot     = true
  deletion_protection     = false
  storage_encrypted       = true
  kms_key_id              = "arn:aws:kms:us-west-2:994788128952:key/f09558be-cedf-45b7-b5ad-7b719215476d"
  publicly_accessible     = false

  # Read replica inherits engine/version/storage from source
  # Do NOT set db_name, username, password — inherited from source

  tags = {
    Name   = "${var.app_name}-dr-replica"
    Role   = "read-replica"
    DR     = "promote-on-failover"
  }
}
