variable "aws_region" {
  description = "AWS Region used for the AWS Provider"
  type        = string
  default     = "eu-west-1"
}

variable "prefix" {
  description = "Prefix for resources"
  type        = string
  default     = "cloudfront-"
}

locals {
  my_ip_address = "${chomp(data.http.icanhazip.response_body)}/32"
}