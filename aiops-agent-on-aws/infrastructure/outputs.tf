output "target_ec2_instance_id" {
  description = "The ID of the EC2 instance being monitored."
  value       = aws_instance.target_ec2.id
}



output "aws_region" {
  value = var.aws_region
}

output "target_ec2_instance_id" {
  description = "The ID of the EC2 instance being monitored."
  value       = aws_instance.target_ec2.id
}

output "dashboard_url" {
  description = "The URL for the Streamlit monitoring dashboard."
  value       = "https://${aws_apprunner_service.frontend_service.service_url}"
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository for the frontend."
  value       = aws_ecr_repository.frontend.repository_url
}