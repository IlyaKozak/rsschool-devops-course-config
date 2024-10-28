variable "aws" {
  description = "aws setup"
  type = object({
    region             = string
  })
  default = {
    region             = "eu-north-1"
  }
}