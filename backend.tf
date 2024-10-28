terraform {
  backend "s3" {
    bucket         = "terraform-20240929182351330400000001"
    key            = "terraform/state-2"
    region         = "eu-north-1"
  }
}

provider "aws" {
  region = var.aws.region
}