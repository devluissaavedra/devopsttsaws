# --- 1. NETWORKING ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- 2. SECURITY GROUPS (Filtros Inteligentes) ---

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg-v2"
  description = "Filtro Capa 7 para trafico web"
  vpc_id      = data.aws_vpc.default.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Preparado para HTTPS (Capa 4.5/7 con SNI futuro)
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
}

resource "aws_security_group" "app_sg" {
  name        = "app-internal-sg"
  description = "Solo permite trafico desde el ALB (Aislamiento total)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Encadenamiento de SGs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. IAM (Roles para Polly) ---

resource "aws_iam_role" "app_role" {
  name = "app_server_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "polly_access" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPollyFullAccess"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "app_instance_profile"
  role = aws_iam_role.app_role.name
}

# --- 4. LOAD BALANCER (El Cerebro) ---

resource "aws_lb" "main_alb" {
  name               = "main-app-alb"
  internal           = false
  load_balancer_type = "application" # Capa 7
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false # Cambiar a true en producción real
}

resource "aws_lb_target_group" "main_tg" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  # Sticky sessions (Opcional, pero util si tu app maneja estado local)
  stickiness {
    type    = "lb_cookie"
    enabled = false # Desactivado por defecto para stateless
  }

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_tg.arn
  }
}

# --- 5. AUTO SCALING (La potencia real) ---

# Plantilla de lo que queremos lanzar
resource "aws_launch_template" "app_template" {
  name_prefix   = "app-v-"
  image_id      = "ami-0ec10929233384c7f"
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

# El grupo que mantiene vivas las instancias
resource "aws_autoscaling_group" "app_asg" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.main_tg.arn]
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.app_template.id
    version = "$Latest"
  }
}

# --- OUTPUT ---
output "alb_url" {
  value       = "http://${aws_lb.main_alb.dns_name}"
  description = "Acceso a la API optimizada"
}