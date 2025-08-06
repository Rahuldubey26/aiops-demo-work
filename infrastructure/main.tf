# infrastructure/main.tf (Corrected for Container Image Deployment)

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- REMOVED: data "archive_file" "anomaly_detector_zip" ---
# This is no longer needed as the anomaly_detector is now a container image.

# Data sources for the remaining zip-based Lambda functions
data "archive_file" "log_analyzer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/log_analyzer_rca"
  output_path = "${path.module}/../dist/log_analyzer_rca.zip"
}

data "archive_file" "remediation_engine_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/remediation_engine"
  output_path = "${path.module}/../dist/remediation_engine.zip"
}

# NOTE: The "get_anomalies_api" Lambda was part of the old React frontend architecture.
# It is NOT needed for the Streamlit architecture. You can safely delete it.
# We will keep it for now but you can remove it to simplify the project.
data "archive_file" "get_anomalies_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/get_anomalies_api"
  output_path = "${path.module}/../dist/get_anomalies_api.zip"
}


# --- Lambda Functions ---

# MODIFIED: This function is now deployed as a container image
resource "aws_lambda_function" "anomaly_detector" {
  function_name = "${var.project_name}-anomaly-detector"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 60
  memory_size   = 512 # Increased memory is good for ML libraries

  # Key change: Deploying from an image in ECR instead of a zip file
  package_type = "Image"
  # The image_uri points to the image that our CI/CD pipeline will build and push
  image_uri    = "${aws_ecr_repository.frontend.repository_url}:anomaly-detector-latest"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.anomalies.arn
      # The model is now in the root of the task, not in /opt/python/
      MODEL_PATH    = "model.joblib"
      RESOURCE_TAG  = "Monitored"
    }
  }
}

# UNCHANGED: This function is simple and can remain a zip file
resource "aws_lambda_function" "log_analyzer_rca" {
  function_name    = "${var.project_name}-log-analyzer-rca"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  filename         = data.archive_file.log_analyzer_zip.output_path
  source_code_hash = data.archive_file.log_analyzer_zip.output_base64sha256
  timeout          = 120

  environment {
    variables = {
      CRITICAL_SNS_TOPIC_ARN = aws_sns_topic.critical_alerts.arn
      DYNAMODB_TABLE_NAME    = aws_dynamodb_table.anomalies.name
    }
  }
}

# UNCHANGED: This function is simple and can remain a zip file
resource "aws_lambda_function" "remediation_engine" {
  function_name    = "${var.project_name}-remediation-engine"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  filename         = data.archive_file.remediation_engine_zip.output_path
  source_code_hash = data.archive_file.remediation_engine_zip.output_base64sha256
  timeout          = 60
}

# UNCHANGED (but optional)
resource "aws_lambda_function" "get_anomalies_api" {
  function_name    = "${var.project_name}-get-anomalies-api"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  filename         = data.archive_file.get_anomalies_api_zip.output_path
  source_code_hash = data.archive_file.get_anomalies_api_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.anomalies.name
    }
  }
}


# --- Lambda Triggers (Unchanged) ---
resource "aws_cloudwatch_event_rule" "every_5_minutes" {
  name                = "${var.project_name}-every-5-minutes"
  description         = "Fires every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "trigger_anomaly_detector" {
  rule      = aws_cloudwatch_event_rule.every_5_minutes.name
  target_id = "TriggerAnomalyDetector"
  arn       = aws_lambda_function.anomaly_detector.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anomaly_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_5_minutes.arn
}

resource "aws_lambda_event_source_mapping" "trigger_log_analyzer" {
  event_source_arn = aws_sns_topic.anomalies.arn
  function_name    = aws_lambda_function.log_analyzer_rca.arn
}

resource "aws_lambda_event_source_mapping" "trigger_remediation_engine" {
  event_source_arn = aws_sns_topic.critical_alerts.arn
  function_name    = aws_lambda_function.remediation_engine.arn
}


# --- DELETED: The entire Lambda Layer section ---
# data "archive_file" "scikit_learn_layer_zip" { ... }
# resource "aws_lambda_layer_version" "scikit_learn_layer" { ... }