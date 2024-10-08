module "sg_load_balancer" {
  source = "terraform-aws-modules/security-group/aws"

  name    = "${var.environment}-${var.context}-${var.task_name}-load-balancer-security-group"
  vpc_id  = var.vpc_id
  tags    = local.tags
  version = "5.1.0"

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "Allow all Outgoing"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Allow http incoming ipv4"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow https incoming ipv4"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  ingress_with_ipv6_cidr_blocks = [
    {
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      description      = "Allow http incoming ipv6"
      ipv6_cidr_blocks = "::/0"
    },
    {
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      description      = "Allow https incoming ipv6"
      ipv6_cidr_blocks = "::/0"
    },
  ]
}

################33333
resource "aws_lb" "load_balancer" {
  name               = "${local.name}-api-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.sg_load_balancer.security_group_id]
  subnets            = [var.public_subnet_ids[0], var.public_subnet_ids[1]]

  enable_deletion_protection = false
  enable_http2               = true
  tags                       = local.tags
}

resource "aws_lb_listener" "load_balancer" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  tags              = local.tags
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

resource "aws_lb_target_group" "target_group" {
  name     = "${local.name}-api-tg"
  port     = var.container_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  load_balancing_algorithm_type = "round_robin"
  slow_start                    = 30
  deregistration_delay          = 300
  target_type                   = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    interval            = var.interval
    matcher             = var.health_code
    path                = var.health_path
    port                = "traffic-port"
    timeout             = var.timeout
    unhealthy_threshold = var.unhealthy_threshold
  }
}

####################
resource "aws_lb_listener_rule" "redirect_apidoc_to_oxolodoc" {
  listener_arn = aws_lb_listener.load_balancer.arn
  priority     = 100

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
      host        = var.redirect_host #development.oxolo.com
      path        = "/documentation/"
    }
  }

  condition {
    host_header {
      values = [var.host_header] #api.development.oxolo.com
    }
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}

module "gateway_mgmt_load_balancer" {
  source  = "git.oxolo.com/platformengineering/load-balancer/aws"
  version = "0.7.2"
  config = {
    vpc_id              = var.vpc_id
    environment         = var.environment
    context             = var.context
    security_group_ids  = [module.sg_load_balancer.security_group_id]
    subnet_ids          = [var.private_subnet_ids[0], var.private_subnet_ids[1]]
    name                = "${var.task_name}-mgmt"
    certificate_arn     = var.certificate_arn
    http_only           = true
    port                = var.mgmt_container_port #8001
    path                = var.mgmt_health_path    #"/status"
    health_code         = var.mgmt_health_code    #200
    unhealthy_threshold = var.unhealthy_threshold
    tags                = local.tags
    internal            = true
    target_type         = "ip"
  }
  depends_on = [
    module.sg_load_balancer
  ]
}
############################## Monitoring ########################################

resource "aws_sns_topic" "fargate_lb_alarms_topic" {
  name = "fargate-lb-alarms-topic"
}
resource "aws_sns_topic_subscription" "lb_email_subscription" {
  topic_arn = aws_sns_topic.fargate_lb_alarms_topic.arn
  protocol  = "email"
  endpoint  = var.slack_endpoint
}

resource "aws_cloudwatch_metric_alarm" "lb_http_4xx_errors" {
  alarm_name          = "${local.name}-http-4xx-errors-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  threshold           = 20

  dimensions = {
    LoadBalancer = aws_lb.load_balancer.arn_suffix
    TargetGroup  = aws_lb_target_group.target_group.arn_suffix
  }

  alarm_description         = "This metric monitors ELB 4XX errors"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.fargate_lb_alarms_topic.arn]
  insufficient_data_actions = [aws_sns_topic.fargate_lb_alarms_topic.arn]
  tags = {
    Name = "http-4xx-error-alarm"
  }
  treat_missing_data  = "notBreaching"
  datapoints_to_alarm = 1
  extended_statistic  = "p99"
}

resource "aws_cloudwatch_metric_alarm" "lb_http_5xx_errors" {
  alarm_name          = "${local.name}-http-5xx-errors-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  threshold           = 10

  dimensions = {
    LoadBalancer = aws_lb.load_balancer.arn_suffix
    TargetGroup  = aws_lb_target_group.target_group.arn_suffix
  }

  alarm_description         = "This metric monitors ELB 5XX errors"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.fargate_lb_alarms_topic.arn]
  insufficient_data_actions = [aws_sns_topic.fargate_lb_alarms_topic.arn]
  tags = {
    Name = "http-5xx-error-alarm"
  }
  treat_missing_data  = "notBreaching"
  datapoints_to_alarm = 1
  extended_statistic  = "p99"
}
resource "aws_cloudwatch_metric_alarm" "lb_latency_high" {
  alarm_name          = "${local.name}-lb-latency-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  threshold           = 5000 # 5 second

  dimensions = {
    TargetGroup  = aws_lb_target_group.target_group.arn_suffix
    LoadBalancer = aws_lb.load_balancer.arn_suffix
  }

  alarm_description         = "This metric monitors the average latency of the ELB"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.fargate_lb_alarms_topic.arn]
  insufficient_data_actions = [aws_sns_topic.fargate_lb_alarms_topic.arn]
  tags = {
    Name = "high-latency-alarm"
  }
  treat_missing_data  = "notBreaching"
  datapoints_to_alarm = 1
  extended_statistic  = "p99"
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    LoadBalancer = aws_lb.load_balancer.arn_suffix
    TargetGroup  = aws_lb_target_group.target_group.arn_suffix
  }

  alarm_description = "Alarm when the number of unhealthy hosts is greater than or equal to the threshold."
  actions_enabled   = true
  alarm_actions     = [aws_sns_topic.fargate_lb_alarms_topic.arn]
  tags = {
    Name = "unhealthy-hosts-alarm"
  }
}