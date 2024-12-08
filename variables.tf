variable "aws_region" {
  description = "aws region"
  type        = string
  default     = "eu-north-1"
}

variable "aws_az" {
  description = "aws az"
  type        = string
  default     = "eu-north-1a"
}

variable "domain" {
  description = "domain"
  type        = string
}

variable "grafana_dashboard_url" {
  description = "grafana dashboard url"
  type        = string
  default     = "https://raw.githubusercontent.com/IlyaKozak/rsschool-devops-course-config/refs/heads/task-8-grafana/grafana-dashboard-model.json"
}

variable "grafana_password" {
  description = "grafana password"
  type        = string
}

variable "jenkins" {
  description = "jenkins variables"
  type        = map(string)
  default = {
    namespace   = "jenkins",
    volume_size = "8Gi",
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
  description = "Private SSH key path on local machine"
  type        = string
  default     = "~/.ssh/aws_jump_host.pem"
}

variable "sonarqube" {
  description = "sonarqube variables"
  type        = map(string)
  default = {
    namespace   = "sonarqube",
    volume_size = "4Gi",
    volume_type = "gp3",
    pv          = "sonarqube-pv",
    pvc         = "sonarqube-claim"
  }
}

variable "ssl_cert" {
  description = "ssl certificate for domain"
  type        = string
  sensitive   = true
}

variable "ssl_key" {
  description = "ssl key for domain"
  type        = string
  sensitive   = true
}

variable "traefik_nodeport" {
  description = "traefik nodeport for web"
  type        = string
  default     = "30080"
}