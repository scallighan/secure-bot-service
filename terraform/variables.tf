variable "subscription_id" {
  type = string
  sensitive = true
}

variable "location" {
  type    = string
  default = "East US"
}

variable "gh_repo" {
  type = string
}

variable "bot_tenant_id" {
  type = string
  sensitive = true
  
}

variable "custom_bot_domain" {
  type = string
}

variable "ai_foundry_agent_id" {
  type = string
}

variable "ai_foundry_endpoint" {
  type = string
}

variable "ai_foundry_rg_id" {
  type = string
}