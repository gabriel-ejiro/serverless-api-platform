terraform {
  required_version = ">= 1.6.0"
  backend "s3" {
    bucket = "tf-state-0000000000000-eu-north-1" 
    key    = "tfstate/serverless-api-platform.tfstate"
    region = "eu-north-1"
    encrypt = true
  }


  required_providers {
    aws     = { source = "hashicorp/aws",     version = "~> 5.60" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random",  version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
}

locals {
  project = "serverless-api-platform"
  tags = {
    Project = local.project
    Env     = "dev"
  }
}

# -------------------------
# DynamoDB (On-Demand)
# -------------------------
resource "aws_dynamodb_table" "items" {
  name         = "${local.project}-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = local.tags
}

# -------------------------
# Lambda role + permissions
# -------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.project}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_app" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.items.arn]
  }

  statement {
    actions   = ["events:PutEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_app" {
  name   = "${local.project}-lambda-app"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_app.json
}

# -------------------------
# CloudWatch Logs for Lambda
# -------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.project}-fn"
  retention_in_days = 7
  tags              = local.tags
}

# -------------------------
# Package Lambda from /lambda
# -------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda.zip"
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.project}-fn"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "app.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  memory_size      = 128
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.items.name
    }
  }

  tags = local.tags
}

# -------------------------
# API Gateway HTTP API
# -------------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.project}-http"
  protocol_type = "HTTP"
  tags          = local.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

# Public route for quick sanity check (no auth)
resource "aws_apigatewayv2_route" "public" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /public"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

# -------------------------
# Cognito: User Pool + Client + Domain
# -------------------------
resource "aws_cognito_user_pool" "pool" {
  name                     = "${local.project}-users"
  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]
  tags                     = local.tags
}

resource "aws_cognito_user_pool_client" "client" {
  name                          = "${local.project}-web"
  user_pool_id                  = aws_cognito_user_pool.pool.id
  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"

  # Hosted UI via implicit flow (GUI-only token capture)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows  = ["implicit"]
  allowed_oauth_scopes = ["openid", "email", "profile"]
  supported_identity_providers = ["COGNITO"]

  # Postman OAuth callback (no code needed)
  callback_urls = ["https://oauth.pstmn.io/v1/callback"]
  logout_urls   = ["https://oauth.pstmn.io/v1/callback"]
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${local.project}-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

# JWT Authorizer for HTTP API
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http.id
  name             = "${local.project}-cog"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.client.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.pool.id}"
  }
}

# Protected route (requires JWT)
resource "aws_apigatewayv2_route" "items" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /items"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Default stage, auto-deploy on changes
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# -------------------------
# EventBridge: log events
# -------------------------
resource "aws_cloudwatch_log_group" "eventbridge" {
  name              = "/aws/events/${local.project}"
  retention_in_days = 7
  tags              = local.tags
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events_to_logs" {
  name               = "${local.project}-events-logs-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "events_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [aws_cloudwatch_log_group.eventbridge.arn]
  }
}

resource "aws_iam_role_policy" "events_logs" {
  role   = aws_iam_role.events_to_logs.id
  policy = data.aws_iam_policy_document.events_logs.json
}

resource "aws_cloudwatch_event_rule" "api_events" {
  name          = "${local.project}-rule"
  event_pattern = jsonencode({ "source": ["serverless.api"] })
}

resource "aws_cloudwatch_event_target" "to_logs" {
  rule     = aws_cloudwatch_event_rule.api_events.name
  arn      = aws_cloudwatch_log_group.eventbridge.arn
  role_arn = aws_iam_role.events_to_logs.arn
}
