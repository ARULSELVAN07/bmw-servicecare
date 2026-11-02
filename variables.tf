variable "aws_region" {
  description = "AWS region for the service deployment."
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Prefix used to name BMW ServiceCare resources."
  type        = string
  default     = "bmw-servicecare"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}
