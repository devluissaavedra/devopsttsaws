# --- 1. NETWORKING (Usando la infraestructura por defecto) ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- 2. SECURITY GROUPS ---

# SG para el Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Permitir trafico HTTP externo"
  vpc_id      = data.aws_vpc.default.id

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
}

# SG para las EC2 (Solo acepta trafico del ALB)
resource "aws_security_group" "fastapi_sg" {
  name        = "fastapi-sg-v2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. PERMISOS (IAM) ---
# (Se mantiene igual a tu archivo original)
resource "aws_iam_role" "ec2_polly_role" {
  name = "ec2_polly_role_v2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "polly_attach" {
  role       = aws_iam_role.ec2_polly_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPollyFullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_polly_profile_v2"
  role = aws_iam_role.ec2_polly_role.name
}

# --- 4. LOAD BALANCER ---

resource "aws_lb" "fastapi_alb" {
  name               = "fastapi-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "fastapi_tg" {
  name     = "fastapi-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.fastapi_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi_tg.arn
  }
}

# --- 5. INSTANCIAS EC2 (2 unidades) ---

resource "aws_instance" "app_server" {
  count         = 2
  ami           = "ami-0ec10929233384c7f"
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.fastapi_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              EOF

  tags = {
    Name = "FastAPI-Server-${count.index + 1}"
  }
}

# Registro de las instancias en el Target Group
resource "aws_lb_target_group_attachment" "tg_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.fastapi_tg.arn
  target_id        = aws_instance.app_server[count.index].id
  port             = 80
}

# --- OUTPUT ---
output "alb_dns_name" {
  value = aws_lb.fastapi_alb.dns_name
  description = "URL publica para acceder a la API"
}