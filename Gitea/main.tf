terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
  access_key = ""
  secret_key = ""
}

resource "aws_instance" "Gitea6" {
  ami           = "ami-0e86e20dae9224db8"
  instance_type = "t2.micro"


  # Security group with port 3000 open
  vpc_security_group_ids = ["sg-0c7afe0b5de7787ea"]

  # User data script to install Docker and run Gitea
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable" -y
    sudo apt install docker-ce -y
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    sudo systemctl start docker
    sudo systemctl enable docker

    # Create directories for Docker Compose setup
    mkdir -p /home/ubuntu/gitea

    # Write the docker-compose.yml file
    cat <<EOT >> /home/ubuntu/gitea/docker-compose.yml
    version: "3"
    
    networks:
        gitea:
            external: false
    
    services:
        server:
            image: gitea/gitea:1.16.5
            container_name: gitea
            environment:
                - USER_UID=1000
                - USER_GID=1000
            restart: always
            networks:
                - gitea
            volumes:
                - ./gitea:/data
                - /etc/timezone:/etc/timezone:ro
                - /etc/localtime:/etc/localtime:ro
            ports:
                - "0.0.0.0:3000:3000"
                - "0.0.0.0:2222:22"
    EOT

    # Run Docker Compose
    cd /home/ubuntu/gitea
    sudo docker-compose up -d
  EOF
  tags = {
    Name = "AutomateGitea6"
  }
}

#  ALB
resource "aws_lb" "gitea_alb" {
  name               = "gitea-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-0c7afe0b5de7787ea"]
  subnets            = ["subnet-0fce7bd95abc75326", "subnet-01ea079b360542567"]  

  tags = {
    Name = "Gitea-ALB"
  }
}

#  Target Group for EC2 instance running Gitea
resource "aws_lb_target_group" "gitea_tg" {
  name        = "gitea-tg"
  port        = 3000  # Gitea is running on port 3000
  protocol    = "HTTP"
  vpc_id      = "vpc-0c88338dcc2287a94"  
  target_type = "instance"

  health_check {
    path                = "/"
    port                = "3000"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "Gitea-TargetGroup"
  }
}

# HTTPS Listener for the ALB
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.gitea_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"  
  certificate_arn   = "arn:aws:acm:us-east-1:709444042708:certificate/e6f22bcd-9f73-4957-9908-fb2ea3cb08e9"  

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitea_tg.arn
  }
}

# Attach EC2 instance to Target Group
resource "aws_lb_target_group_attachment" "gitea_tg_attachment" {
  target_group_arn = aws_lb_target_group.gitea_tg.arn
  target_id        = aws_instance.Gitea6.id
  port             = 3000
}


