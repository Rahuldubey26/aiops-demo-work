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

# Data sources for packaging Lambda functions
data "archive_file" "anomaly_detector_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/anomaly_detector"
  output_path = "${path.module}/../dist/anomaly_detector.zip"
}

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

data "archive_file" "get_anomalies_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/get_anomalies_api"
  output_path = "${path.module}/../dist/get_anomalies_api.zip"
}


# Lambda Functions
resource "aws_lambda_function" "anomaly_detector" {
  function_name    = "${var.project_name}-anomaly-detector"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  filename         = data.archive_file.anomaly_detector_zip.output_path
  source_code_hash = data.archive_file.anomaly_detector_zip.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.anomalies.arn
      MODEL_PATH    = "model.joblib"
      RESOURCE_TAG  = "Monitored"
    }
  }
}

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

resource "aws_lambda_function" "remediation_engine" {
  function_name    = "${var.project_name}-remediation-engine"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  filename         = data.archive_file.remediation_engine_zip.output_path
  source_code_hash = data.archive_file.remediation_engine_zip.output_base64sha256
  timeout          = 60
}

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

# Lambda Triggers
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