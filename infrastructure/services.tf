#------------------------------------------------------------------------------
# Monitoring Target
#------------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "target_ec2" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  key_name      = var.ec2_key_name # Assumes you have a variable for the key pair name
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name      = "${var.project_name}-target-instance"
    Monitored = "true" # Tag used by the anomaly detector Lambda to find this resource
  }
}

#------------------------------------------------------------------------------
# Backend Alerting and Data Storage
#------------------------------------------------------------------------------

# SNS Topic for initial, unverified anomalies
resource "aws_sns_topic" "anomalies" {
  name = "${var.project_name}-anomalies"
}

# SNS Topic for critical, verified alerts that trigger remediation
resource "aws_sns_topic" "critical_alerts" {
  name = "${var.project_name}-critical-alerts"
}

# Subscription to send critical alerts to an email address
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# DynamoDB Table to store all detected events for the frontend dashboard
resource "aws_dynamodb_table" "anomalies" {
  name           = "${var.project_name}-anomalies"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "${var.project_name} Anomalies Table"
  }
}

#------------------------------------------------------------------------------
# Frontend Service (Streamlit on AWS App Runner)
#------------------------------------------------------------------------------

# 1. ECR Repository to store the frontend Docker image
resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}/frontend"
  image_tag_mutability = "MUTABLE" # Allows overwriting the 'latest' tag

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 2. App Runner Service to host the Streamlit Dashboard
resource "aws_apprunner_service" "frontend_service" {
  service_name = "${var.project_name}-dashboard"

  # Source is the Docker image in our ECR repository
  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.app_runner_ecr_access_role.arn
    }
    image_repository {
      image_identifier      = "${aws_ecr_repository.frontend.repository_url}:latest"
      image_repository_type = "ECR"
      image_configuration {
        port = "8501" # Port exposed in the Dockerfile
        runtime_environment_variables = {
          # Pass the DynamoDB table name to the Streamlit app
          DYNAMODB_TABLE_NAME = aws_dynamodb_table.anomalies.name
          AWS_REGION          = var.aws_region
        }
      }
    }
    auto_deployments_enabled = true # Automatically redeploy when a new image is pushed to ECR
  }
  
  # Configuration for the compute instance running the app
  instance_configuration {
    cpu               = "1024" # 1 vCPU
    memory            = "4096" 
    instance_role_arn = aws_iam_role.app_runner_instance_role.arn # Grants permissions to the running container
  }

  # How App Runner checks if the service is healthy
  health_check_configuration {
    protocol            = "TCP"
    interval            = 20 # seconds
    timeout             = 10 # seconds
    healthy_threshold   = 1  # count
    unhealthy_threshold = 5  # count
  }

  tags = {
    Name = "${var.project_name} Streamlit Dashboard"
  }

  # Ensure the IAM role for ECR access exists before creating the service
   depends_on = [
    aws_iam_role_policy_attachment.app_runner_ecr_attach
  ]
}