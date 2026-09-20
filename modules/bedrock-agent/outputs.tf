output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_api.assistant.api_endpoint
}

output "chat_url" {
  description = "Chat endpoint URL"
  value       = "${aws_apigatewayv2_api.assistant.api_endpoint}/chat"
}

output "evaluate_url" {
  description = "Evaluation endpoint URL"
  value       = "${aws_apigatewayv2_api.assistant.api_endpoint}/evaluate"
}

output "lambda_function_name" {
  description = "Assistant Lambda function name"
  value       = aws_lambda_function.assistant.function_name
}

output "dynamodb_table" {
  description = "DynamoDB session memory table"
  value       = aws_dynamodb_table.sessions.name
}

output "chat_example" {
  description = "Example curl command to test the chat API"
  value       = <<-EOT
    # Start a conversation
    curl -X POST ${aws_apigatewayv2_api.assistant.api_endpoint}/chat \
      -H "Content-Type: application/json" \
      -d '{"session_id":"user-123","message":"Show me watches under $150"}'

    # Continue same session (memory retained)
    curl -X POST ${aws_apigatewayv2_api.assistant.api_endpoint}/chat \
      -H "Content-Type: application/json" \
      -d '{"session_id":"user-123","message":"Is it in stock?"}'

    # Evaluate a response
    curl -X POST ${aws_apigatewayv2_api.assistant.api_endpoint}/evaluate \
      -H "Content-Type: application/json" \
      -d '{"message":"Show me watches","answer":"We have an elegant gold watch for $109.99, in stock."}'
  EOT
}
