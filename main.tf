provider "aws" {
  region = "us-east-1"
}

# --- 1. CAPA DE RED ---
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "vpc-lab-universidad" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# --- 2. CAPA DE SEGURIDAD ---
resource "aws_security_group" "web_sg" {
  name        = "ec2-rds-x"
  description = "HTTP entrante"
  vpc_id      = aws_vpc.main_vpc.id

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

resource "aws_security_group" "db_sg" {
  name        = "rds-ec2-x"
  description = "Trafico PostgreSQL estricto desde SG web"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
}

# --- 3. CAPA DE COMPUTO ---
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro" 
  subnet_id     = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd postgresql15
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Infraestructura AWS desplegada con Terraform</h1><p>Conexion PostgreSQL lista. Credenciales en Secrets Manager.</p>" > /var/www/html/index.html
              EOF

  tags = { Name = "Web-Server-EC2" }
}

# --- 4. CAPA DE DATOS ---
resource "aws_db_subnet_group" "db_subnet" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}

resource "aws_db_instance" "postgres_db" {
  allocated_storage           = 20
  engine                      = "postgres"
  engine_version              = "15"
  instance_class              = "db.t3.micro"
  db_name                     = "appdb"
  username                    = "dbadmin"
  manage_master_user_password = true
  multi_az                    = false
  skip_final_snapshot         = true
  db_subnet_group_name        = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  publicly_accessible         = false
}

output "url_servidor_web" {
  value = "http://${aws_instance.web_server.public_ip}"
}
