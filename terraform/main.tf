terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.22.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
    azapi = {
      source = "azure/azapi"
      version = "=2.3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = var.subscription_id
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

data "azurerm_client_config" "current" {}

data "azurerm_log_analytics_workspace" "default" {
  name                = "DefaultWorkspace-${data.azurerm_client_config.current.subscription_id}-${local.loc_short}"
  resource_group_name = "DefaultResourceGroup-${local.loc_short}"
} 

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.gh_repo}-${random_string.unique.result}-${local.loc_for_naming}"
  location = var.location
  tags = local.tags
}

resource "azurerm_virtual_network" "default" {
  name                = "vnet-${local.func_name}-${local.loc_for_naming}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.39.0.0/16"]

  tags = local.tags
}

resource "azurerm_subnet" "default" {
  name                 = "default-subnet-${local.loc_for_naming}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.39.0.0/24"]
}

resource "azurerm_subnet" "cluster" {
  name                 = "cluster-subnet-${local.loc_for_naming}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.39.1.0/24"]

  delegation {
    name = "Microsoft.App/environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  
  }
}

# create NSG for the subnet
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80","443"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAppGW"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["65200-65535"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.default.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_association2" {
  subnet_id                 = azurerm_subnet.cluster.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}


resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.func_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  enable_rbac_authorization  = true

}

resource "azurerm_role_assignment" "kv_officer" {
  scope                            = azurerm_key_vault.kv.id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_cert_officer" {
  scope                            = azurerm_key_vault.kv.id
  role_definition_name             = "Key Vault Certificates Officer"
  principal_id                     = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_certificate" "cert" {
  depends_on = [ azurerm_role_assignment.kv_cert_officer ]
  name         = "wildcard-scallighan-cert"
  key_vault_id = azurerm_key_vault.kv.id
  certificate {
    contents = filebase64("wildcard.pfx")
  }
}


resource "azurerm_application_insights" "app" {
  name                = "${local.func_name}-insights"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  application_type    = "other"
  workspace_id        = data.azurerm_log_analytics_workspace.default.id
}


# create a public ip adress for the application gateway
resource "azurerm_public_ip" "app_gateway" {
  name                = "pip-appgw-${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}

# create an application gateway
resource "azurerm_application_gateway" "app_gateway" {
  name                = "appgw-${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku {
    name     = "Basic"
    tier     = "Basic"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.default.id
  }

  frontend_port {
    name = "appgw-frontend-port"
    port = 80
  }

  frontend_port {
    name = "appgw-frontend-port-https"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.app_gateway.id
  }

  backend_address_pool {
    name  = "appgw-backend-pool"
    fqdns = [azurerm_container_app.agent.ingress[0].fqdn]
  }

  backend_http_settings {
    name                  = "appgw-backend-https-settings"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 20
    probe_name = "https-healthz"
    host_name = azurerm_container_app.agent.ingress[0].fqdn

  }

  http_listener {
    name                           = "appgw-http-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "appgw-frontend-port"
    protocol                       = "Http"
  }

  http_listener {
    name                          = "appgw-https-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "appgw-frontend-port-https"
    protocol                       = "Https"
    ssl_certificate_name           = "wildcard"
  }

  request_routing_rule {
    name                       = "appgw-routing-rule"
    priority                    = 10
    rule_type                  = "Basic"
    http_listener_name         = "appgw-http-listener"
    backend_address_pool_name  = "appgw-backend-pool"
    backend_http_settings_name = "appgw-backend-https-settings"
  }

  request_routing_rule {
    name                       = "appgw-routing-rule-https"
    priority                    = 20
    rule_type                  = "Basic"
    http_listener_name         = "appgw-https-listener"
    backend_address_pool_name  = "appgw-backend-pool"
    backend_http_settings_name = "appgw-backend-https-settings"
  }

  probe {
    name = "https-healthz"
    protocol = "Https"
    path = "/"
    interval = 30
    timeout = 30
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-401"]
    }
  }

  probe {
    name = "http-healthz"
    protocol = "Http"
    path = "/"
    interval = 30
    timeout = 30
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-401"]
    }
  }


  ssl_certificate {
    name = "wildcard"
    key_vault_secret_id = "https://${azurerm_key_vault.kv.name}.vault.azure.net/secrets/wildcard-scallighan-cert"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [ azurerm_user_assigned_identity.appgw.id
    ]
  }
  tags = local.tags

}

resource "azurerm_user_assigned_identity" "appgw" {
  location            = azurerm_resource_group.rg.location
  name                = "uai-appgw-${local.func_name}"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "app_gateway_secrets" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw.principal_id
}

resource "azurerm_role_assignment" "app_gateway_certs" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = azurerm_user_assigned_identity.appgw.principal_id
}

resource "azurerm_private_dns_zone" "ace" {
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = azurerm_resource_group.rg.name
  tags = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "ace" {
  name                  = "link-${azurerm_container_app_environment.this.name}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.ace.name
  virtual_network_id    = azurerm_virtual_network.default.id

  registration_enabled = false
}
resource "azurerm_private_dns_a_record" "ace" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.ace.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 3600
  records             = [azurerm_container_app_environment.this.static_ip_address]
}



resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.rg.location
  name                = "uai-${local.func_name}"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "containerapptokv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_container_app_environment" "this" {
  name                       = "ace-${local.func_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.default.id

  infrastructure_subnet_id = azurerm_subnet.cluster.id

  internal_load_balancer_enabled = true

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.tags
  lifecycle {
    ignore_changes = [
     infrastructure_resource_group_name,
     log_analytics_workspace_id
    ]
  }
}

resource "azurerm_container_app" "agent" {
  name                         = "aca-${local.func_name}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  template {
    container {
      name   = "agent"
      image  = "ghcr.io/scallighan/secure-bot-service:latest"
      cpu    = 0.25
      memory = "0.5Gi"
      # env {
      #   name = "AAD_APP_CLIENT_ID"
      #   secret_name = "aad-app-client-id"
      # }
      # env {
      #   name = "AAD_APP_CLIENT_SECRET"
      #   secret_name = "aad-app-client-secret"
      # }

      # env {
      #   name = "AAD_APP_TENANT_ID"
      #   secret_name = "aad-app-tenant-id"
      # }

      # env {
      #   name = "BOT_DOMAIN"
      #   secret_name = "bot-domain"
      # }

      # env {
      #   name = "BOT_ID"
      #   secret_name = "bot-id"
      # }

      # env {
      #   name = "BOT_PASSWORD"
      #   secret_name = "bot-password"
      # }

      # env {
      #   name = "BACKEND_CLIENT_ID"
      #   secret_name = "backend-client-id"
      # }

      # env {
      #   name = "AAD_APP_OAUTH_AUTHORITY_HOST"
      #   value = "https://login.microsoftonline.com"
      # }

      env {
        name = "RUNNING_ON_AZURE"
        value = "1"
      }

      env {
        name = "tenantId"
        value = var.bot_tenant_id
      }

      env {
        name = "clientId"
        value = azurerm_user_assigned_identity.bot.client_id
      }

      # env {
      #   name = "BASE_URL"
      #   value = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
      # }
      
     
    }
    http_scale_rule {
      name                = "http-1"
      concurrent_requests = "100"
    }
    min_replicas = 0
    max_replicas = 1
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 3978
    transport                  = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # secret {
  #   name = "aad-app-client-id"
  #   identity = azurerm_user_assigned_identity.this.id
  #   key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/AAD-APP-CLIENT-ID"
  # }
  # secret {
  #   name = "aad-app-client-secret"
  #   identity = azurerm_user_assigned_identity.this.id
  #   key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/AAD-APP-CLIENT-SECRET"
  # }

  # secret {
  #   name = "aad-app-tenant-id"
  #   identity = azurerm_user_assigned_identity.this.id
  #   key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/AAD-APP-TENANT-ID"
  # }
  # secret {
  #   name = "bot-domain"
  #   identity = azurerm_user_assigned_identity.this.id
  #   key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/BOT-DOMAIN"
  # }
  # secret {
  #   name = "bot-id"
  #   identity = azurerm_user_assigned_identity.this.id
  #   key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/BOT-ID"
  # }
  # secret {
  #   name = "bot-password"
  #   identity = azurerm_user_assigned_identity.this.id
  #   key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/BOT-PASSWORD"
  # }

  # secret {
  #   name = "backend-client-id"
  #   identity = azurerm_user_assigned_identity.this.id
  #   key_vault_secret_id = "${azurerm_key_vault.kv.vault_uri}secrets/VITE-BACKEND-CLIENT-ID"
  # }   

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id, azurerm_user_assigned_identity.bot.id]
  }
  tags = local.tags

  lifecycle {
    ignore_changes = [ secret ]
  }
}

resource "azurerm_user_assigned_identity" "bot" {
  location            = azurerm_resource_group.rg.location
  name                = "uai-bot-${local.func_name}"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azapi_resource" "teamsbot" {
  type = "Microsoft.BotService/botServices@2023-09-15-preview"
  name = "bot-${local.func_name}"
  location = "global"
  parent_id = azurerm_resource_group.rg.id
  tags = local.tags
  body = {
    properties = {
      displayName = "bot-${local.func_name}"
      endpoint = "https://${var.custom_bot_domain}/api/messages"
      msaAppId = "${azurerm_user_assigned_identity.bot.client_id}"
      msaAppMSIResourceId = "${azurerm_user_assigned_identity.bot.id}"
      msaAppTenantId	= "${data.azurerm_client_config.current.tenant_id}"
      msaAppType = "UserAssignedMSI"
    }
    sku = {
      name = "F0"
    }
    kind = "azurebot"
  }
}