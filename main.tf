terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}


locals {
  environment = "prod"

  backend-app-name = "${local.environment}-agh-event-hub-api"
  rg-name          = "${local.environment}-rg"
  sp-name          = "${local.environment}-sp"
  acr-name         = "${local.environment}agheventhubacr"

  docker_image_tag = data.external.deployed-app-docker-tag.result["docker_image_tag"] != "" ? data.external.deployed-app-docker-tag.result["docker_image_tag"] : "latest"
}

data "external" "deployed-app-docker-tag" {
  program = ["./_utils/find-deployed-app-docker-tag.sh", "${local.rg-name}", "${local.backend-app-name}"]
}


# ===============================================================================
# REGISTER BACKEDN RESOURCE GROUP AND PLAN
# ===============================================================================

resource "azurerm_resource_group" "rg" {
  name     = local.rg-name
  location = "Poland Central"

  tags = {
    env = "${local.environment}"
  }
}

resource "azurerm_service_plan" "sp" {
  name                = local.sp-name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "F1"
  tags = {
    env = "${local.environment}"
  }
}


# ===============================================================================
# REGISTER CONTAINER REGISTRY
# ===============================================================================

resource "azurerm_container_registry" "acr" {
  name                   = local.acr-name
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  sku                    = "Standard"
  anonymous_pull_enabled = true

  tags = {
    env = "${local.environment}"
  }
}


# ===============================================================================
# REGISTER BACKEND API
# ===============================================================================

resource "azurerm_linux_web_app" "backend-app" {
  name                = local.backend-app-name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.sp.location
  service_plan_id     = azurerm_service_plan.sp.id

  site_config {
    always_on = false

    application_stack {
      docker_image     = "docker.io/enriquecatala/fastapi-helloworld"
      docker_image_tag = local.docker_image_tag
    }
  }

  app_settings = {
    WEBSITES_PORT = 5000

    HELLOWORLD_ENV = "Hello"
  }

  tags = {
    env = "${local.environment}"
  }
}


# ===============================================================================
# REGISTER TODO
# ===============================================================================


# resource "azurerm_postgresql_server" "example" {
#   name                = "postgresql-server-1"
#   location            = azurerm_resource_group.example.location
#   resource_group_name = azurerm_resource_group.example.name

#   sku_name = "B_Gen5_2"

#   storage_mb                   = 5120
#   backup_retention_days        = 7
#   geo_redundant_backup_enabled = false
#   auto_grow_enabled            = true

#   administrator_login          = "psqladmin"
#   administrator_login_password = "H@Sh1CoR3!"
#   version                      = "9.5"
#   ssl_enforcement_enabled      = true
# }

# resource "azurerm_postgresql_database" "example" {
#   name                = "exampledb"
#   resource_group_name = azurerm_resource_group.example.name
#   server_name         = azurerm_postgresql_server.example.name
#   charset             = "UTF8"
#   collation           = "English_United States.1252"
# }


# data "azurerm_client_config" "current" {}

# resource "azurerm_resource_group" "example" {
#   name     = "example-resources"
#   location = "West Europe"
# }

# resource "azurerm_key_vault" "example" {
#   name                        = "examplekeyvault"
#   location                    = azurerm_resource_group.example.location
#   resource_group_name         = azurerm_resource_group.example.name
#   enabled_for_disk_encryption = true
#   tenant_id                   = data.azurerm_client_config.current.tenant_id
#   soft_delete_retention_days  = 7
#   purge_protection_enabled    = false

#   sku_name = "standard"

#   access_policy {
#     tenant_id = data.azurerm_client_config.current.tenant_id
#     object_id = data.azurerm_client_config.current.object_id

#     key_permissions = [
#       "Get",
#     ]

#     secret_permissions = [
#       "Get",
#     ]

#     storage_permissions = [
#       "Get",
#     ]
#   }
# }
