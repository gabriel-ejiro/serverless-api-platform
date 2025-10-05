output "api_base_url" {
  value       = aws_apigatewayv2_api.http.api_endpoint
  description = "HTTP API base URL"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.domain.domain
  description = "Cognito Hosted UI domain prefix"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.pool.id
  description = "Cognito User Pool ID"
}

output "cognito_client_id" {
  value       = aws_cognito_user_pool_client.client.id
  description = "Cognito App Client ID"
}
