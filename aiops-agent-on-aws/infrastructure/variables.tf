variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "A unique name for the project to prefix resources."
  type        = string
  default     = "aiops-agent"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "alert_email" {
  description = "Email address to send SNS alerts to."
  type        = string
  // Note: You must confirm the subscription manually via email.
}

variable "ec2_key_name" {
  description = "The name of the EC2 Key Pair to allow SSH access to the target instance."
  type        = string
}