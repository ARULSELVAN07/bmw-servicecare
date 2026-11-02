data "aws_caller_identity" "current" {}

locals {
  name = "${var.project_name}-${var.environment}"
  cognito_domain_prefix = replace(
    lower("${var.project_name}-${var.environment}-${substr(data.aws_caller_identity.current.account_id, 0, 8)}"),
    "_",
    "-",
  )
  tags = {
    Application = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table" "service_requests" {
  name         = "${local.name}-requests"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ticket_id"

  attribute {
    name = "ticket_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.tags
}

resource "aws_s3_bucket" "knowledge" {
  bucket = "${local.name}-knowledge-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "knowledge" {
  bucket = aws_s3_bucket.knowledge.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge" {
  bucket = aws_s3_bucket.knowledge.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "knowledge" {
  bucket                  = aws_s3_bucket.knowledge.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name}-frontend-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend"
  description                       = "Private access to the ServiceCare frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  comment             = "${local.name} frontend"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "${local.name}-frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "${local.name}-frontend-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 86400

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
        }
      }
    }]
  })
}

resource "aws_cognito_user_pool" "servicecare" {
  name = "${local.name}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  tags = local.tags
}

resource "aws_cognito_user_pool_domain" "servicecare" {
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.servicecare.id
}

resource "aws_cognito_user_group" "service_advisors" {
  name         = "ServiceAdvisors"
  description  = "BMW ServiceCare advisors authorized to update requests"
  user_pool_id = aws_cognito_user_pool.servicecare.id
}

resource "aws_cognito_user_pool_client" "servicecare" {
  name                                 = "${local.name}-web-client"
  user_pool_id                         = aws_cognito_user_pool.servicecare.id
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${aws_cloudfront_distribution.frontend.domain_name}/auth/callback"]
  logout_urls                          = ["https://${aws_cloudfront_distribution.frontend.domain_name}/"]
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
}

resource "aws_sns_topic" "request_notifications" {
  name = "${local.name}-notifications"
  tags = local.tags
}

resource "aws_cloudwatch_event_bus" "servicecare" {
  name = "${local.name}-events"
  tags = local.tags
}

resource "aws_sqs_queue" "request_notifications" {
  name                       = "${local.name}-notifications"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  sqs_managed_sse_enabled    = true
  tags                       = local.tags
}

resource "aws_sqs_queue_policy" "request_notifications" {
  queue_url = aws_sqs_queue.request_notifications.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.request_notifications.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.request_created.arn
        }
      }
    }]
  })
}

resource "aws_iam_role" "lambda_execution" {
  name = "${local.name}-lambda-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_servicecare" {
  name = "${local.name}-servicecare-access"
  role = aws_iam_role.lambda_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.service_requests.arn
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.servicecare.arn
      }
    ]
  })
}

resource "aws_iam_role" "step_functions_execution" {
  name = "${local.name}-workflow-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "step_functions_notifications" {
  name = "${local.name}-workflow-notifications"
  role = aws_iam_role.step_functions_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = aws_sns_topic.request_notifications.arn
    }]
  })
}

resource "aws_sfn_state_machine" "request_workflow" {
  name     = "${local.name}-request-workflow"
  role_arn = aws_iam_role.step_functions_execution.arn
  definition = jsonencode({
    StartAt = "SendNotification"
    States = {
      SendNotification = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.request_notifications.arn
          Subject     = "New BMW ServiceCare request"
          "Message.$" = "States.JsonToString($.detail)"
        }
        End = true
      }
    }
  })
  tags       = local.tags
  depends_on = [aws_iam_role_policy.step_functions_notifications]
}

resource "aws_iam_role" "eventbridge_workflow" {
  name = "${local.name}-events-start-workflow"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "eventbridge_workflow" {
  name = "${local.name}-events-start-workflow"
  role = aws_iam_role.eventbridge_workflow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.request_workflow.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "request_created" {
  name           = "${local.name}-request-created"
  event_bus_name = aws_cloudwatch_event_bus.servicecare.name
  event_pattern = jsonencode({
    source        = ["bmw.servicecare"]
    "detail-type" = ["ServiceRequestCreated"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "request_queue" {
  rule           = aws_cloudwatch_event_rule.request_created.name
  event_bus_name = aws_cloudwatch_event_bus.servicecare.name
  target_id      = "ServiceRequestQueue"
  arn            = aws_sqs_queue.request_notifications.arn
}

resource "aws_cloudwatch_event_target" "request_workflow" {
  rule           = aws_cloudwatch_event_rule.request_created.name
  event_bus_name = aws_cloudwatch_event_bus.servicecare.name
  target_id      = "ServiceRequestWorkflow"
  arn            = aws_sfn_state_machine.request_workflow.arn
  role_arn       = aws_iam_role.eventbridge_workflow.arn
}

data "archive_file" "create_ticket" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/create-ticket/handler.py"
  output_path = "${path.module}/.terraform/create-ticket.zip"
}

data "archive_file" "get_ticket" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/get-ticket/handler.py"
  output_path = "${path.module}/.terraform/get-ticket.zip"
}

data "archive_file" "update_ticket" {
  type        = "zip"
  source_file = "${path.module}/lambda-code/update-ticket/handler.py"
  output_path = "${path.module}/.terraform/update-ticket.zip"
}

resource "aws_lambda_function" "create_ticket" {
  function_name    = "${local.name}-create-ticket"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.create_ticket.output_path
  source_code_hash = data.archive_file.create_ticket.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      REQUESTS_TABLE = aws_dynamodb_table.service_requests.name
      EVENTS_BUS     = aws_cloudwatch_event_bus.servicecare.name
    }
  }
  tags = local.tags
}

resource "aws_lambda_function" "get_ticket" {
  function_name    = "${local.name}-get-ticket"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_ticket.output_path
  source_code_hash = data.archive_file.get_ticket.output_base64sha256
  timeout          = 15

  environment {
    variables = { REQUESTS_TABLE = aws_dynamodb_table.service_requests.name }
  }
  tags = local.tags
}

resource "aws_lambda_function" "update_ticket" {
  function_name    = "${local.name}-update-ticket"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.update_ticket.output_path
  source_code_hash = data.archive_file.update_ticket.output_base64sha256
  timeout          = 15

  environment {
    variables = { REQUESTS_TABLE = aws_dynamodb_table.service_requests.name }
  }
  tags = local.tags
}

resource "aws_api_gateway_rest_api" "servicecare" {
  name = "${local.name}-api"
  endpoint_configuration { types = ["REGIONAL"] }
  tags = local.tags
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${local.name}-cognito"
  rest_api_id     = aws_api_gateway_rest_api.servicecare.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.servicecare.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_resource" "tickets" {
  rest_api_id = aws_api_gateway_rest_api.servicecare.id
  parent_id   = aws_api_gateway_rest_api.servicecare.root_resource_id
  path_part   = "tickets"
}

resource "aws_api_gateway_resource" "ticket_id" {
  rest_api_id = aws_api_gateway_rest_api.servicecare.id
  parent_id   = aws_api_gateway_resource.tickets.id
  path_part   = "{ticket_id}"
}

resource "aws_api_gateway_method" "cors" {
  for_each = {
    tickets   = aws_api_gateway_resource.tickets.id
    ticket_id = aws_api_gateway_resource.ticket_id.id
  }

  rest_api_id   = aws_api_gateway_rest_api.servicecare.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors" {
  for_each = aws_api_gateway_method.cors

  rest_api_id       = aws_api_gateway_rest_api.servicecare.id
  resource_id       = each.value.resource_id
  http_method       = each.value.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "cors" {
  for_each = aws_api_gateway_method.cors

  rest_api_id = aws_api_gateway_rest_api.servicecare.id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "cors" {
  for_each = aws_api_gateway_integration.cors

  rest_api_id = aws_api_gateway_rest_api.servicecare.id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  status_code = aws_api_gateway_method_response.cors[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.servicecare.id
  response_type = "DEFAULT_4XX"
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,PUT'"
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_5xx" {
  rest_api_id   = aws_api_gateway_rest_api.servicecare.id
  response_type = "DEFAULT_5XX"
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,PUT'"
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_method" "create_ticket" {
  rest_api_id   = aws_api_gateway_rest_api.servicecare.id
  resource_id   = aws_api_gateway_resource.tickets.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_method" "get_ticket" {
  rest_api_id   = aws_api_gateway_rest_api.servicecare.id
  resource_id   = aws_api_gateway_resource.ticket_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_method" "update_ticket" {
  rest_api_id   = aws_api_gateway_rest_api.servicecare.id
  resource_id   = aws_api_gateway_resource.ticket_id.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "create_ticket" {
  rest_api_id             = aws_api_gateway_rest_api.servicecare.id
  resource_id             = aws_api_gateway_resource.tickets.id
  http_method             = aws_api_gateway_method.create_ticket.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.create_ticket.invoke_arn
}

resource "aws_api_gateway_integration" "get_ticket" {
  rest_api_id             = aws_api_gateway_rest_api.servicecare.id
  resource_id             = aws_api_gateway_resource.ticket_id.id
  http_method             = aws_api_gateway_method.get_ticket.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_ticket.invoke_arn
}

resource "aws_api_gateway_integration" "update_ticket" {
  rest_api_id             = aws_api_gateway_rest_api.servicecare.id
  resource_id             = aws_api_gateway_resource.ticket_id.id
  http_method             = aws_api_gateway_method.update_ticket.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.update_ticket.invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  for_each = {
    create = aws_lambda_function.create_ticket.function_name
    get    = aws_lambda_function.get_ticket.function_name
    update = aws_lambda_function.update_ticket.function_name
  }

  statement_id  = "AllowApiGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.servicecare.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "servicecare" {
  rest_api_id = aws_api_gateway_rest_api.servicecare.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.create_ticket.id,
      aws_api_gateway_method.get_ticket.id,
      aws_api_gateway_method.update_ticket.id,
      aws_api_gateway_integration.create_ticket.id,
      aws_api_gateway_integration.get_ticket.id,
      aws_api_gateway_integration.update_ticket.id,
      values(aws_api_gateway_method.cors)[*].id,
      values(aws_api_gateway_integration.cors)[*].id,
      values(aws_api_gateway_method_response.cors)[*].id,
      values(aws_api_gateway_integration_response.cors)[*].id,
      aws_api_gateway_gateway_response.cors_4xx.id,
      aws_api_gateway_gateway_response.cors_5xx.id,
    ]))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [
    aws_api_gateway_integration.create_ticket,
    aws_api_gateway_integration.get_ticket,
    aws_api_gateway_integration.update_ticket,
    aws_api_gateway_integration.cors,
    aws_api_gateway_method_response.cors,
    aws_api_gateway_integration_response.cors,
    aws_api_gateway_gateway_response.cors_4xx,
    aws_api_gateway_gateway_response.cors_5xx,
  ]
}

resource "aws_api_gateway_stage" "servicecare" {
  deployment_id = aws_api_gateway_deployment.servicecare.id
  rest_api_id   = aws_api_gateway_rest_api.servicecare.id
  stage_name    = var.environment
  tags          = local.tags
}

resource "aws_wafv2_web_acl" "servicecare_api" {
  name  = "${local.name}-api"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-api-waf"
    sampled_requests_enabled   = true
  }
  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "servicecare_api" {
  resource_arn = aws_api_gateway_stage.servicecare.arn
  web_acl_arn  = aws_wafv2_web_acl.servicecare_api.arn
}
