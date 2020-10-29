provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 0.12.7, < 0.14"

  required_providers {
    aws = "2.63.0"
  }

  backend "s3" {
    bucket         = "apigw-sqs-salesforce"
    key            = "non-prod/dev.tfstate"
    region         = "us-east-1"
    dynamodb_table = "s3-state-lock"
    encrypt        = true
  }
}



# ----------------------------------------------------------------------
# SQS
# ----------------------------------------------------------------------

resource "aws_sqs_queue" "terraform_queue" {
  name                        = var.sqs_queue_name
  tags = {
    Environment = "Non-Prod"
  }
}




# ----------------------------------------------------------------------
# Cloudwatch role and policy
# ----------------------------------------------------------------------

resource "aws_api_gateway_account" "demo" {
  cloudwatch_role_arn = aws_iam_role.apiSQS.arn
}


resource "aws_iam_role_policy" "cloudwatch" {
  name = "default"
  role = aws_iam_role.apiSQS.id
  policy = templatefile("policies/api-gateway-permission.json", {
    sqs_arn = aws_sqs_queue.terraform_queue.arn
  })
}

# ----------------------------------------------------------------------
# API Gateway
# ----------------------------------------------------------------------
resource "aws_iam_role" "apiSQS" {
  name = "apigateway_sqs"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "api_policy" {
  name   = "api-sqs-cloudwatch-policy"
  policy = templatefile("policies/api-gateway-permission.json", {
    sqs_arn = aws_sqs_queue.terraform_queue.arn
  })
}

resource "aws_iam_policy" "sqs_policy" {
  name   = "api-sqs-consumer-policy"
  policy = templatefile("policies/sqs-consumer-permission.json", {
    sqs_arn = aws_sqs_queue.terraform_queue.arn
  })
}

resource "aws_iam_role_policy_attachment" "api_exec_role" {
  role       = aws_iam_role.apiSQS.name
  policy_arn = aws_iam_policy.api_policy.arn
}

###Endpoint creation for api gateway
resource "aws_api_gateway_rest_api" "apiGateway" {
  name        = var.api_gateway_name
  description = "POST records to SQS queue"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {
          "AWS": "*"
        },
        "Action": "execute-api:Invoke",
        "Resource": "execute-api:/*/*/*",
         "Condition": {
          "IpAddress": {"aws:SourceIp": ${jsonencode(var.whitelist)}}
        }
      }
    ]
  }
POLICY
}    


resource "aws_api_gateway_resource" "sfdata" {
  rest_api_id = aws_api_gateway_rest_api.apiGateway.id
  parent_id   = aws_api_gateway_rest_api.apiGateway.root_resource_id
  path_part   = var.apigw_resource_path_name
}

resource "aws_api_gateway_method" "method_sfdata" {
  rest_api_id   = aws_api_gateway_rest_api.apiGateway.id
  resource_id   = aws_api_gateway_resource.sfdata.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

###API gateway integration with SQS
resource "aws_api_gateway_integration" "api" {
  rest_api_id             = aws_api_gateway_rest_api.apiGateway.id
  resource_id             = aws_api_gateway_resource.sfdata.id
  http_method             = aws_api_gateway_method.method_sfdata.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.apiSQS.arn
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${aws_sqs_queue.terraform_queue.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  passthrough_behavior = "NEVER"

  # Request Template for passing Method, Body, QueryParameters and PathParams to SQS messages
  request_templates = {
    "application/json" = <<EOF
Action=SendMessage##
&MessageBody=$util.urlEncode($input.body)##
EOF
  }

  depends_on = [
    aws_iam_role_policy_attachment.api_exec_role
  ]
}

# ----------------------------------------------------------------------
# API Key
# ----------------------------------------------------------------------
resource "aws_api_gateway_api_key" "api_key" {
  name        = "${var.app_name}-key"
  description = "API Key for salesforce data"
}

# ----------------------------------------------------------------------
# Usage Plan
# ----------------------------------------------------------------------
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.app_name}-usage-plan"
  description = "Usage plan for salesforce data"
  api_stages {
    api_id = aws_api_gateway_rest_api.apiGateway.id
    stage  = aws_api_gateway_deployment.api.stage_name
  }
}

# ----------------------------------------------------------------------
# API Key - Usage Plan Mapping
# ----------------------------------------------------------------------
resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
}

# ----------------------------------------------------------------------
# Mapping SQS response
# ----------------------------------------------------------------------
resource "aws_api_gateway_method_response" "http200" {
  rest_api_id = aws_api_gateway_rest_api.apiGateway.id
  resource_id = aws_api_gateway_resource.sfdata.id
  http_method = aws_api_gateway_method.method_sfdata.http_method
  status_code = 200
}

resource "aws_api_gateway_integration_response" "http200" {
  rest_api_id       = aws_api_gateway_rest_api.apiGateway.id
  resource_id       = aws_api_gateway_resource.sfdata.id
  http_method       = aws_api_gateway_method.method_sfdata.http_method
  status_code       = aws_api_gateway_method_response.http200.status_code
  selection_pattern = "^2[0-9][0-9]" // regex pattern for any 200 message that comes back from SQS

  depends_on = [
    aws_api_gateway_integration.api
  ]
}

# Deployment
resource "aws_api_gateway_deployment" "api" {
 rest_api_id = aws_api_gateway_rest_api.apiGateway.id
 stage_name  = var.environment

 depends_on = [
   aws_api_gateway_integration.api,
 ]

 # Redeploy when there are new updates
 triggers = {
   redeployment = sha1(join(",", list(
     jsonencode(aws_api_gateway_integration.api),
   )))
 }

 lifecycle {
   create_before_destroy = true
 }
}

# ----------------------------------------------------------------------
# Cloudwatch log monitoring
# ----------------------------------------------------------------------
resource "aws_api_gateway_method_settings" "general_settings" {
  rest_api_id = aws_api_gateway_rest_api.apiGateway.id
  stage_name  = aws_api_gateway_deployment.api.stage_name
  method_path = "${aws_api_gateway_resource.sfdata.path_part}/${aws_api_gateway_method.method_sfdata.http_method}"

  settings {
    # Enable CloudWatch logging and metrics
    metrics_enabled        = true
    data_trace_enabled     = true
    logging_level          = "INFO"

    # Limit the rate of calls to prevent abuse and unwanted charges
    throttling_rate_limit  = 1000
    throttling_burst_limit = 500
  }
}
