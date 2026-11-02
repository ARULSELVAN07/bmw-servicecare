output "api_url" {
  description = "Base URL for the authenticated ServiceCare REST API."
  value       = aws_api_gateway_stage.servicecare.invoke_url
}

output "cognito_user_pool_id" {
  description = "Cognito user pool used by the API authorizer."
  value       = aws_cognito_user_pool.servicecare.id
}

output "cognito_app_client_id" {
  description = "Public Cognito app client ID for the web frontend."
  value       = aws_cognito_user_pool_client.servicecare.id
}

output "service_requests_table_name" {
  description = "DynamoDB table storing service requests."
  value       = aws_dynamodb_table.service_requests.name
}

output "knowledge_bucket_name" {
  description = "Private S3 bucket for knowledge documents."
  value       = aws_s3_bucket.knowledge.id
}

output "frontend_url" {
  description = "CloudFront URL for the ServiceCare frontend."
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "frontend_bucket_name" {
  description = "Private S3 bucket for deployed frontend assets."
  value       = aws_s3_bucket.frontend.id
}

output "frontend_distribution_id" {
  description = "CloudFront distribution ID for frontend cache invalidation."
  value       = aws_cloudfront_distribution.frontend.id
}

output "cognito_domain_url" {
  description = "Cognito hosted sign-in domain used by the frontend."
  value       = "https://${aws_cognito_user_pool_domain.servicecare.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "service_advisors_group_name" {
  description = "Cognito group required for advisor request updates."
  value       = aws_cognito_user_group.service_advisors.name
}
