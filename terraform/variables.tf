variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-north-1"
}

variable "my_ip" {
  description = "Your public IP in CIDR form (x.x.x.x/32), the only address allowed to SSH in"
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && endswith(var.my_ip, "/32")
    error_message = "my_ip must be a single IP address ending in /32."
  }
}
