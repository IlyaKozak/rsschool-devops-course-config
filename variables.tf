variable "aws_region" {
  description = "aws region"
  type        = string
  default     = "eu-north-1"
}

variable "private_key" {
  description = "Private SSH key for remote access"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Private SSH path on local machine"
  type        = string
}

variable "k3s_token" {
  description = "k3s token"
  type        = string
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

variable "is_local_setup" {
  description = "if true prepare ssh and k3s configs on local machine for kubectl and helm"
  type        = bool
}