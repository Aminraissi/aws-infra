# ---------------------------------------------------------------
# Product AI Assistant
# Lambda + API Gateway + DynamoDB (memory) + Bedrock Claude
# Cost: ~$0.003 per conversation, no idle cost
# ---------------------------------------------------------------

# ── DynamoDB for conversation memory ─────────────────────────
resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project_name}-chat-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  range_key    = "timestamp"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = { Name = "${var.project_name}-chat-sessions" }
}

# ── IAM Role for Lambda ───────────────────────────────────────
resource "aws_iam_role" "lambda_assistant" {
  name = "${var.project_name}-assistant-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-assistant-lambda-role" }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_assistant.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "assistant-permissions"
  role = aws_iam_role.lambda_assistant.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.model_id}",
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.judge_model_id}",
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.model_id}",
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.judge_model_id}",
          "arn:aws:bedrock:*::foundation-model/anthropic.*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = [
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.sessions.arn
      }
    ]
  })
}

# ── Lambda function code ──────────────────────────────────────
data "archive_file" "assistant_lambda" {
  type        = "zip"
  output_path = "${path.module}/assistant.zip"

  source {
    content  = file("${path.module}/lambda/assistant.py")
    filename = "lambda_function.py"
  }

  source {
    content  = file("${path.module}/lambda/products.json")
    filename = "products.json"
  }
}

resource "aws_lambda_function" "assistant" {
  filename         = data.archive_file.assistant_lambda.output_path
  function_name    = "${var.project_name}-assistant"
  role             = aws_iam_role.lambda_assistant.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.assistant_lambda.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE      = aws_dynamodb_table.sessions.name
      MODEL_ID            = var.model_id
      AWS_REGION_NAME     = data.aws_region.current.name
      LANGFUSE_PUBLIC_KEY = var.langfuse_public_key
      LANGFUSE_SECRET_KEY = var.langfuse_secret_key
      LANGFUSE_HOST       = var.langfuse_host
    }
  }

  tags = { Name = "${var.project_name}-assistant" }
}

# ── API Gateway ───────────────────────────────────────────────
resource "aws_apigatewayv2_api" "assistant" {
  name          = "${var.project_name}-assistant-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["Content-Type", "Authorization"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = { Name = "${var.project_name}-assistant-api" }
}

resource "aws_apigatewayv2_integration" "assistant" {
  api_id                 = aws_apigatewayv2_api.assistant.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.assistant.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "chat" {
  api_id    = aws_apigatewayv2_api.assistant.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.assistant.id}"
}

resource "aws_apigatewayv2_route" "evaluate" {
  api_id    = aws_apigatewayv2_api.assistant.id
  route_key = "POST /evaluate"
  target    = "integrations/${aws_apigatewayv2_integration.assistant.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.assistant.id
  name        = "$default"
  auto_deploy = true

  tags = { Name = "${var.project_name}-assistant-stage" }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.assistant.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.assistant.execution_arn}/*/*"
}

# ── Data Sources ──────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
