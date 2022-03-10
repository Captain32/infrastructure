terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region = var.aws_region
  assume_role {
    role_arn = var.role_arn
  }
}

resource "aws_vpc" "default" {
  cidr_block = "10.${var.cidr_numeral}.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_name
  }
}

resource "aws_subnet" "public" {
  count = length(split(",", var.availability_zones))
  vpc_id = aws_vpc.default.id

  cidr_block = "10.${var.cidr_numeral}.${lookup(var.cidr_numeral_public, count.index)}.0/24"
  availability_zone = element(split(",", var.availability_zones), count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet${count.index}-${var.vpc_name}"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "igw-${var.vpc_name}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = {
    Name = "rt-${var.vpc_name}"
  }
}

resource "aws_route_table_association" "public" {
  count = length(split(",", var.availability_zones))
  subnet_id = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app" {
  name = "app_security_group"
  vpc_id = aws_vpc.default.id

  ingress = [
    {
      description = ""
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = [
        "0.0.0.0/0"
      ]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self = false
    },
    {
      description = ""
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = []
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = [
        aws_security_group.loadBalancer_sg.id]
      self = false
    },
    {
      description = ""
      from_port = 443
      to_port = 443
      protocol = "tcp"
      cidr_blocks = []
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = [
        aws_security_group.loadBalancer_sg.id]
      self = false
    },
    {
      description = ""
      from_port = 8080
      to_port = 8080
      protocol = "tcp"
      cidr_blocks = []
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = [
        aws_security_group.loadBalancer_sg.id]
      self = false
    }
  ]

  egress = [
    {
      description = ""
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = [
        "0.0.0.0/0"
      ]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]
}

resource "aws_security_group" "db" {
  name = "db_security_group"
  vpc_id = aws_vpc.default.id

  ingress = [
    {
      description = ""
      from_port = 3306
      to_port = 3306
      protocol = "tcp"
      cidr_blocks = [
        aws_vpc.default.cidr_block
      ]
      security_groups = [
        aws_security_group.app.id
      ]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      self = false
    }
  ]

  egress = [
    {
      description = ""
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = [
        "0.0.0.0/0"
      ]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]
}

resource "aws_kms_key" "s3key" {
  description = "used for s3 bucket"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "alias_s3" {
  name = "alias/s3_key"
  target_key_id = aws_kms_key.s3key.key_id
}

resource "aws_s3_bucket" "s3bucket" {
  bucket = "db.${var.domain}"
  acl = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3key.arn
        sse_algorithm = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id = "log"
    enabled = true

    prefix = "log/"

    tags = {
      rule = "log"
      autoclean = "true"
    }

    transition {
      days = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_db_parameter_group" "default" {
  name = "rds-mysql"
  family = "mysql8.0"

  parameter {
    name = "performance_schema"
    value = true
    apply_method = "pending-reboot"
  }
}

resource "aws_db_subnet_group" "default" {
  name = "db-subnet-group"
  subnet_ids = aws_subnet.public.*.id
}

resource "aws_db_instance" "default" {
  engine = "mysql"
  engine_version = "8.0.17"
  instance_class = "db.t3.micro"
  multi_az = false
  identifier = "csye6225"
  username = "csye6225"
  password = var.db_password
  db_subnet_group_name = aws_db_subnet_group.default.name
  publicly_accessible = false
  name = "csye6225"
  parameter_group_name = aws_db_parameter_group.default.name
  vpc_security_group_ids = [
    aws_security_group.db.id
  ]
  allocated_storage = 10
  skip_final_snapshot = true
  backup_retention_period = 1
  availability_zone = element(split(",", var.availability_zones), 0)
  kms_key_id = aws_kms_key.rds_key.arn
  storage_encrypted = true
}

resource "aws_db_instance" "replica" {
  engine = "mysql"
  engine_version = "8.0.17"
  instance_class = "db.t3.micro"
  identifier = "csye6225-replica"
  username = "csye6225"
  password = var.db_password
  publicly_accessible = false
  name = "csye6225"
  parameter_group_name = aws_db_parameter_group.default.name
  vpc_security_group_ids = [
    aws_security_group.db.id
  ]
  allocated_storage = 10
  skip_final_snapshot = true
  replicate_source_db = aws_db_instance.default.identifier
  availability_zone = element(split(",", var.availability_zones), 1)
  kms_key_id = aws_kms_key.rds_key.arn
  storage_encrypted = true
}

resource "aws_iam_role" "role" {
  name = "EC2-CSYE6225"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid = ""
      },
    ]
  })
}

resource "aws_iam_instance_profile" "profile" {
  name = "ec2_profile"
  role = aws_iam_role.role.name
}

resource "aws_iam_policy" "policy" {
  name = "WebAppS3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObjectVersion",
          "s3:ListBucketVersions",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.s3bucket.id}",
          "arn:aws:s3:::${aws_s3_bucket.s3bucket.id}/*"
        ]
      },
      {
        Action = [
          "kms:*",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "policy_CodeDeploy_EC2_S3" {
  name = "CodeDeploy-EC2-S3"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucketVersions",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::codedeploy.example.me/*",
          "arn:aws:s3:::codedeploy.example.me"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "role_policy_attach" {
  policy_arn = aws_iam_policy.policy.arn
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy_attachment" "role_policy_attach1" {
  policy_arn = aws_iam_policy.policy_CodeDeploy_EC2_S3.arn
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy_attachment" "role_policy_attach2" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy_attachment" "role_policy_attach3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy_attachment" "role_policy_attach4" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role = aws_iam_role.role.name
}

resource "aws_iam_role" "code_deploy_role" {
  name = "CodeDeployServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

# Attach policy to CodeDeploy role
resource "aws_iam_role_policy_attachment" "role_policy_attach5" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role = aws_iam_role.code_deploy_role.name
}

resource "aws_iam_user_policy_attachment" "ghactions_lamda_update_attach" {
  user = "ghactions-app"
  policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
}

# Codedeploy app
resource "aws_codedeploy_app" "app" {
  compute_platform = "Server"
  name = "csye6225-webapp"
}

# Codedeply group
resource "aws_codedeploy_deployment_group" "group" {
  app_name = aws_codedeploy_app.app.name
  deployment_group_name = "csye6225-webapp-deployment"
  deployment_config_name = "CodeDeployDefault.OneAtATime"
  service_role_arn = aws_iam_role.code_deploy_role.arn
  autoscaling_groups = [
    aws_autoscaling_group.autoscaling_group.name
  ]

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.target_group.name
    }
  }

  ec2_tag_filter {
    key = "Name"
    type = "KEY_AND_VALUE"
    value = "CodeDeploy Instance"
  }

  deployment_style {
    deployment_type = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = true
    events = [
      "DEPLOYMENT_FAILURE"
    ]
  }
}

data "aws_ami" "ami" {
  owners = [
    var.acc_id]
  most_recent = true
}

/*resource "aws_instance" "app" {
  ami = data.aws_ami.ami.id
  instance_type = "t2.micro"
  disable_api_termination = false
  associate_public_ip_address = true
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
    delete_on_termination = true
  }
  vpc_security_group_ids = [
    aws_security_group.app.id
  ]
  iam_instance_profile = aws_iam_instance_profile.profile.name
  subnet_id = element(aws_subnet.public.*.id, 0)
  key_name = "rsa_root"
  tags = {
    Name = "CodeDeploy Instance"
  }
  depends_on = [
    aws_db_instance.default]
  user_data = <<EOF
#!/bin/bash
echo 'export BUCKET_NAME=${aws_s3_bucket.s3bucket.bucket}' | sudo tee -a /etc/environment
echo 'export RDS_HOSTNAME=${aws_db_instance.default.address}' | sudo tee -a /etc/environment
echo 'export RDS_PORT=${aws_db_instance.default.port}' | sudo tee -a /etc/environment
echo 'export RDS_DB_NAME=${aws_db_instance.default.name}' | sudo tee -a /etc/environment
echo 'export RDS_USERNAME=${aws_db_instance.default.username}' | sudo tee -a /etc/environment
echo 'export RDS_PASSWORD=${aws_db_instance.default.password}' | sudo tee -a /etc/environment
  EOF
}*/

data "aws_route53_zone" "hosted_zone" {
  name = var.domain
}

resource "aws_route53_record" "route53_record" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name = data.aws_route53_zone.hosted_zone.name
  type = "A"

  alias {
    name = aws_lb.application_Load_Balancer.dns_name
    zone_id = aws_lb.application_Load_Balancer.zone_id
    evaluate_target_health = true
  }
}

resource "aws_launch_configuration" "launch_config" {
  name = "asg_launch_config"
  image_id = data.aws_ami.ami.id
  instance_type = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.profile.name
  associate_public_ip_address = true
  key_name = "rsa_root"
  security_groups = [
    aws_security_group.app.id
  ]
  user_data = <<EOF
#!/bin/bash
echo 'export BUCKET_NAME=${aws_s3_bucket.s3bucket.bucket}' | sudo tee -a /etc/environment
echo 'export RDS_HOSTNAME=${aws_db_instance.default.address}' | sudo tee -a /etc/environment
echo 'export RDS_PORT=${aws_db_instance.default.port}' | sudo tee -a /etc/environment
echo 'export RDS_DB_NAME=${aws_db_instance.default.name}' | sudo tee -a /etc/environment
echo 'export RDS_USERNAME=${aws_db_instance.default.username}' | sudo tee -a /etc/environment
echo 'export RDS_PASSWORD=${aws_db_instance.default.password}' | sudo tee -a /etc/environment
echo 'export RDS_REPLICA_HOSTNAME=${aws_db_instance.replica.address}' | sudo tee -a /etc/environment
echo "export TOPIC_ARN=${aws_sns_topic.notifications.arn}" | sudo tee -a /etc/environment
echo "export DYNAMO_TABLE=${aws_dynamodb_table.token_table.name}" | sudo tee -a /etc/environment
echo "export DOMAIN=${var.domain}" | sudo tee -a /etc/environment
  EOF
  root_block_device {
    volume_type = "gp2"
    volume_size = 20
    delete_on_termination = true
    encrypted = true
  }
}

resource "aws_autoscaling_group" "autoscaling_group" {
  name = "autoscaling_group"
  launch_configuration = aws_launch_configuration.launch_config.name
  min_size = 3
  max_size = 5
  default_cooldown = 60
  desired_capacity = 3
  tag {
    key = "Name"
    propagate_at_launch = true
    value = "CodeDeploy Instance"
  }
  target_group_arns = [
    aws_lb_target_group.target_group.arn
  ]
  vpc_zone_identifier = aws_subnet.public.*.id
}

resource "aws_autoscaling_policy" "scale_up" {
  name = "scale_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name = "scale_down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 60
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
}

resource "aws_cloudwatch_metric_alarm" "CPUAlarmHigh" {
  alarm_name = "CPUAlarmHigh"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = 60
  statistic = "Average"
  threshold = 05

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }

  alarm_description = "Scale-up if CPU > 5% for 1 minutes"
  alarm_actions = [
    aws_autoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "CPUAlarmLow" {
  alarm_name = "CPUAlarmLow"
  comparison_operator = "LessThanThreshold"
  evaluation_periods = 2
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = 60
  statistic = "Average"
  threshold = 03

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }

  alarm_description = "Scale-down if CPU < 3% for 1 minutes"
  alarm_actions = [
    aws_autoscaling_policy.scale_down.arn]
}

resource "aws_lb_target_group" "target_group" {
  name = "lbTargetGroup"
  port = "8080"
  protocol = "HTTP"
  vpc_id = aws_vpc.default.id
  tags = {
    name = "lbTargetGroup"
  }
  health_check {
    healthy_threshold = 3
    unhealthy_threshold = 5
    timeout = 5
    interval = 30
    path = "/healthstatus"
    port = "8080"
    matcher = "200"
  }
}

resource "aws_security_group" "loadBalancer_sg" {
  name = "loadBalance_security_group"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }
  //  ingress {
  //    from_port = 80
  //    to_port = 80
  //    protocol = "tcp"
  //    cidr_blocks = [
  //      "0.0.0.0/0"]
  //  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"]
  }
}

resource "aws_lb" "application_Load_Balancer" {
  name = "application-Load-Balancer"
  internal = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.loadBalancer_sg.id]
  subnets = aws_subnet.public.*.id
  ip_address_type = "ipv4"
}

data "aws_acm_certificate" "aws_ssl_certificate" {
  domain = var.domain
  statuses = [
    "ISSUED"
  ]
}

resource "aws_lb_listener" "webapp-Listener" {
  load_balancer_arn = aws_lb.application_Load_Balancer.arn
  port = "443"
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = data.aws_acm_certificate.aws_ssl_certificate.arn
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

resource "aws_sns_topic" "notifications" {
  name = "user-notifications-topic"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        Action: "sts:AssumeRole",
        Principal: {
          "Service": "lambda.amazonaws.com"
        },
        Effect: "Allow",
        Sid: ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment" {
  role = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment1" {
  role = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment2" {
  role = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "send_email" {
  s3_bucket = "codedeploy.example.me"
  s3_key = "send_email.zip"
  function_name = "send-email"
  role = aws_iam_role.lambda_role.arn
  handler = "send-email.NotifyUser"
  runtime = "python3.7"
}

resource "aws_sns_topic_subscription" "subscription" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol = "lambda"
  endpoint = aws_lambda_function.send_email.arn
}

resource "aws_lambda_permission" "sns_invoke_lambda" {
  statement_id = "AllowExecutionFromSNS"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.send_email.function_name
  principal = "sns.amazonaws.com"
  source_arn = aws_sns_topic.notifications.arn
}

resource "aws_dynamodb_table" "token_table" {
  name = "token_table"
  hash_key = "token"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "token"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled = true
  }
}

resource "aws_kms_key" "ebs_key" {
  description = "KMS for EBS"
  enable_key_rotation = true
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "kms:*",
            "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_ebs_default_kms_key" "default_ebs_kms_key" {
  key_arn = aws_kms_key.ebs_key.arn
}

resource "aws_kms_key" "rds_key" {
  description = "KMS for RDS"
  deletion_window_in_days = 7
  enable_key_rotation = true
}

resource "aws_kms_alias" "alias_ebs" {
  name = "alias/ebs_key"
  target_key_id = aws_kms_key.ebs_key.key_id
}

resource "aws_kms_alias" "alias_rds" {
  name = "alias/rds_key"
  target_key_id = aws_kms_key.rds_key.key_id
}