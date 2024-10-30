variable "aws_region" {
  description = "aws region"
  type        = string
  default     = "eu-north-1"
}

# variable "private_key" {
#   description = "Private SSH key for remote access"
#   type        = string
#   sensitive   = true
# }

variable "k3s_token" {
  description = "k3s token"
  type        = string
  # sensitive   = true
}

variable "jenkins" {
  description = "jenkins variables"
  type        = map(string)
  default = {
    nodeport    = "30080",
    volume_size = "8Gi",
    volume_type = "gp3",
    pv          = "jenkins-pv",
    pvc         = "jenkins-claim"
  }
}

variable "domain" {
  description = "domain for jenkins"
  type        = string
}