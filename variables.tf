variable "aws_region" {
  description = "aws region"
  type        = string
  default     = "eu-north-1"
}

variable "domain" {
  description = "domain"
  type        = string
}

variable "jenkins" {
  description = "jenkins variables"
  type        = map(string)
  default = {
    volume_size = "4Gi",
    volume_type = "gp3",
    pv          = "jenkins-pv",
    pvc         = "jenkins-claim"
  }
}

variable "k3s_token" {
  description = "k3s token"
  type        = string
}

variable "private_key" {
  description = "Private SSH key for remote access"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Private SSH path on local machine"
  type        = string
  default     = "~/.ssh/aws_jump_host.pem"
}

variable "ssl_cert" {
  description = "ssl certificate"
  type        = string
  sensitive   = true
}

variable "ssl_key" {
  description = "ssl key"
  type        = string
  sensitive   = true
}

variable "traefik_nodeport" {
  description = "traefik nodeport for web"
  type        = string
  default     = "30080"
}