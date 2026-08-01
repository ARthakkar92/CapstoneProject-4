# variables.tf
variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "capstone-jenkins"
}

variable "instance_type" {
  default = "t3.small"
}


variable "allowed_ip" {
  description = "Your IP in CIDR form, e.g. 203.0.113.5/32"
  type        = string
}