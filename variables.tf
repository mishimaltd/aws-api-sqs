variable "region" {
  default = "us-east-1"
}

variable "environment" {
  default = "non-prod"
}

variable "app_name" {
  default = "salesforce-pdm-audit-data-app"
}

variable "sqs_queue_name" {}

variable "api_gateway_name" {}

variable "apigw_resource_path_name" {}

variable "whitelist" {
  type    = list(string)
  default = []
}
