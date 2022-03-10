variable "aws_region" {
  default = "us-east-1"
}

variable "aws_profile" {
  description = "The profile name"
}

variable "role_arn" {
  description = "The arn of the role"
}

variable "vpc_name" {
  description = "The name of the VPC"
}

variable "cidr_numeral" {
  description = "The VPC CIDR numeral (10.x.0.0/16)"
}

variable "availability_zones" {
  description = "The zones of the subnets"
}

variable "cidr_numeral_public" {
  description = "The subnet CIDR numeral (10.x.y.0/24)"
}

variable "domain" {
  description = "domain"
}

variable "db_password" {
  description = "db password"
}

variable "acc_id" {
  description = "account id"
}