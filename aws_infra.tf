provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet_1a" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet-1a"
  }
}

resource "aws_subnet" "subnet_1b" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet-1b"
  }
}

resource "aws_subnet" "subnet_1c" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-south-1c"
  tags = {
    Name = "subnet-1c"
  }
}

resource "aws_launch_template" "example" {
  name_prefix   = "example-"
  image_id      = "ami-0f5ee92e2d63afc18"
  instance_type = "t2.micro"
  key_name      = "key.pem"
  
  vpc_security_group_ids = [aws_security_group.auto_scale.id]

  user_data = base64encode(<<EOF
#!/bin/bash
# Install docker and docker-compose
apt-get update
apt-get install -y cloud-utils apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce
usermod -aG docker ubuntu
curl -L https://github.com/docker/compose/releases/download/1.21.0/docker-compose-\$(uname -s)-\$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
EOF
)


block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 15
    }
  }
}


resource "aws_security_group" "auto_scale" {
  #name_prefix = "auto-scale-"
  vpc_id = aws_vpc.my_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow incoming HTTP traffic only from the Load Balancer
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  # Allow incoming SSH traffic only from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["103.98.63.141/32"]
  }
}

resource "aws_autoscaling_group" "example" {
  name                 = "example-asg"
  launch_template {
    id = aws_launch_template.example.id
  }
  vpc_zone_identifier = [aws_subnet.subnet_1a.id]
  min_size             = 1
  max_size             = 3
  desired_capacity    = 1
}

resource "aws_security_group" "load_balancer" {
  #name_prefix = "lb-"
  vpc_id = aws_vpc.my_vpc.id

  # Allow incoming HTTP traffic from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "example" {
  name               = "example-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.load_balancer.id]
  subnets            = [aws_subnet.subnet_1a.id, aws_subnet.subnet_1b.id] #Minimum 2 Subnets from Different AZ
}

resource "aws_lb_target_group" "example" {
  name     = "example-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  default_action {
    target_group_arn = aws_lb_target_group.example.arn
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Hello, world!"
      status_code  = "200"
    }
  }
}

resource "aws_lb_target_group_attachment" "example" {
  target_group_arn = aws_lb_target_group.example.arn
  target_id        = aws_autoscaling_group.example.id
  port             = 80
}

resource "aws_sns_topic" "example" {
  name = "example-sns-topic"
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "cpu-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "300"
  statistic          = "Average"
  threshold          = "75"
  alarm_description  = "Alarm when CPU usage is >= 75%"
  alarm_actions      = [aws_sns_topic.example.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_alarm" {
  alarm_name          = "memory-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name        = "MemoryUtilization"
  namespace          = "System/Linux"
  period             = "300"
  statistic          = "Average"
  threshold          = "75"
  alarm_description  = "Alarm when memory usage is >= 75%"
  alarm_actions      = [aws_sns_topic.example.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }
}

