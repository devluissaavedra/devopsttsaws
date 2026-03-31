# --- 1. GRUPO DE SEGURIDAD ---
resource "aws_security_group" "fastapi_sg" {
  name        = "fastapi-sg"
  description = "Permitir trafico web"

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

# --- 2. PERMISOS (IAM ROLE) ---
resource "aws_iam_role" "ec2_polly_role" {
  name = "ec2_polly_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Política de Polly al Rol
resource "aws_iam_role_policy_attachment" "polly_attach" {
  role       = aws_iam_role.ec2_polly_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPollyFullAccess"
}

# Perfil de instancia (El conector entre el Rol y la EC2)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_polly_profile"
  role = aws_iam_role.ec2_polly_role.name
}

# --- 3. LA INSTANCIA EC2 ---
resource "aws_instance" "app_server" {
  ami           = "ami-0ec10929233384c7f" # Ubuntu 24.04 en us-east-1
  instance_type = "t3.micro"
  
  # Conectamos el Security Group y el Perfil de IAM
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
    Name = "FastAPI-Polly-Server"
  }
}