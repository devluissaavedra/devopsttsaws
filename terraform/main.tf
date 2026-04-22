# --- 1. DATOS DE RED ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- 2. SEGURIDAD (Security Groups) ---

resource "aws_security_group" "alb_sg" {
  name        = "alb-public-sg"
  description = "Capa 7: Solo trafico web publico"
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

resource "aws_security_group" "app_sg" {
  name        = "app-private-sg"
  description = "Aislamiento: Solo trafico desde el ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Encadenamiento
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. COMPONENTE DE BALANCEO ---

resource "aws_lb" "main_alb" {
  name               = "prod-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "main_tg" {
  name     = "app-tg-blue"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  # --- CONNECTION DRAINING CONFIG ---
  deregistration_delay = 300 # 5 min de gracia para sesiones activas

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_tg.arn
  }
}

# --- 4. AUTO SCALING (El Motor) ---

resource "aws_launch_template" "app_lt" {
  name_prefix   = "backend-v-"
  image_id      = "ami-0ec10929233384c7f" # Ubuntu 22.04 LTS
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "asg-backend-main"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.main_tg.arn]
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  # Espera a que el Draining termine antes de marcar la instancia como muerta
  wait_for_capacity_timeout = "10m" 
}

# --- 5. SCALING POLICIES (Automatizacion CloudWatch) ---

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "keep-cpu-at-50"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0 # Target: 50% de uso de CPU promedio
  }
}

# --- OUTPUTS ---
output "dns_endpoint" {
  value       = aws_lb.main_alb.dns_name
  description = "URL del Balanceador de Carga"
}

# ---- CloudWatch
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "DevOps-TTS-Monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            [ "AWS/Polly", "ResponseTime", "Operation", "SynthesizeSpeech" ]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Latencia de Polly"
        }
      },
      {
        type   = "text"
        width  = 12
        height = 6
        properties = {
          markdown = "# DevOps TTS Status\nMonitoreo básico de logs y latencia."
        }
      }
    ]
  })
}