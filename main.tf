
provider "aws" {
    region = var.server_region
    
    # access_key = "set on aws cli"
    # secret_key = " $ aws configure"
}


data "aws_ami" "ubuntu" { 
most_recent = true 
filter { 
name = "name" 
values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"] 
} 
filter { 
name = "virtualization-type" 
values = ["hvm"] 
} 
owners = ["099720109477"] # Canonical }
}

resource "aws_launch_configuration" "example" {
  image_id        = data.aws_ami.ubuntu.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]
  user_data = "${data.template_file.user_data.rendered}"
  

  #using input file as alternative instead of inline user data
  
  
  # user_data =<<-EOF
  #             #!/bin/bash
  #              echo "Hello" > index.html
  #              nohup busybox httpd -f -p ${var.server_port} &
  #              EOF

####

  lifecycle {
    create_before_destroy = true
  }
}
data "template_file" "user_data" {
    template = "${file("templates/user_data.tpl")}"
}







####

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnet_ids.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}



resource "aws_autoscaling_schedule" "scale_up" {
scheduled_action_name = "business-hours"
min_size = 2
max_size = 10
desired_capacity = 10
recurrence = "0 8 * * *"
autoscaling_group_name = aws_autoscaling_group.example.name
}
resource "aws_autoscaling_schedule" "scale_down" {
scheduled_action_name = "night"
min_size = 2
max_size = 10
desired_capacity = 2
recurrence = "0 18 * * *"
autoscaling_group_name = aws_autoscaling_group.example.name
}





resource "aws_autoscaling_policy" "aspolicy" {
  name                   = "a_scalingpolicy"
  scaling_adjustment     = 4
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.example.name
}

resource "aws_cloudwatch_metric_alarm" "bat" {
  alarm_name          = "terraform-alarm-test"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.aspolicy.arn]
}





resource "aws_shield_protection" "example" {
  name         = "example"
  resource_arn = "arn:aws:elasticloadbalancing:us-west-2:930289539424:loadbalancer/app/terraform-asg-example/d248ebbe945c1533"
}



resource "aws_security_group" "instance" {
  name = var.instance_security_group_name

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_lb" "example" {

  name               = var.alb_name

  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = var.tcp
  protocol          = "HTTP"


  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "asg" {

  name = var.alb_name

  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_security_group" "alb" {

  name = var.alb_security_group_name

  # Allow inbound HTTP requests
  ingress {
    from_port   = var.tcp
    to_port     = var.tcp
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}