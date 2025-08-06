resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-lambda-policy"
  description = "Policy for AIOps Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action   = ["sns:Publish"],
        Effect   = "Allow",
        Resource = "*" // For simplicity, restrict to specific SNS topics in production
      },
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:RebootInstances"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Scan"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.anomalies.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# (Keep the existing lambda_exec_role and policies)

# IAM Role for App Runner to access ECR
resource "aws_iam_role" "app_runner_ecr_access_role" {
  name = "${var.project_name}-app-runner-ecr-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "build.apprunner.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "app_runner_ecr_policy" {
  name = "${var.project_name}-app-runner-ecr-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:BatchCheckLayerAvailability"
      ],
      Effect   = "Allow",
      Resource = aws_ecr_repository.frontend.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_runner_ecr_attach" {
  role       = aws_iam_role.app_runner_ecr_access_role.name
  policy_arn = aws_iam_policy.app_runner_ecr_policy.arn
}

# IAM Role for the Streamlit app instance to access DynamoDB
resource "aws_iam_role" "app_runner_instance_role" {
  name = "${var.project_name}-app-runner-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "tasks.apprunner.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_runner_dynamodb_access" {
  role       = aws_iam_role.app_runner_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess" # For simplicity, can be scoped down
}



