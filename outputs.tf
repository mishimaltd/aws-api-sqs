output "Queue_id" {
  description = "THe ID of the AWS SQS"
  value       = aws_sqs_queue.terraform_queue.id
}

output "API_Invoke_URL" {
  description = "THe invoke url for AWS apigateway"
  value       = aws_api_gateway_deployment.api.invoke_url
}

output "api_key" {
  value = aws_api_gateway_api_key.api_key.value
}
