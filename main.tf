terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.70.0"
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

  backend-app-name           = "${local.environment}-agh-event-hub-api"
  backend-app-db-server-name = "${local.environment}-agh-event-hub-server-db"
  backend-app-db-name        = "${local.environment}-agh-event-hub-db"
  rg-name                    = "${local.environment}-rg"
  sp-name                    = "${local.environment}-sp"
  acr-name                   = "${local.environment}agheventhubacr"
  key-vault-name             = "${local.environment}agheventhubkeyvault"

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
# REGISTER SECRET KEY VAULT
# ===============================================================================

resource "random_password" "db-password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "key-vault" {
  name                       = local.key-vault-name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "premium"
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
      "List"
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover",
      "List"
    ]

    storage_permissions = [
      "Get",
      "List"
    ]
  }

  tags = {
    env = "${local.environment}"
  }
}

resource "azurerm_key_vault_secret" "db-admin-password" {
  name         = "${local.backend-app-db-server-name}-admin-password"
  value        = random_password.db-password.result
  key_vault_id = azurerm_key_vault.key-vault.id
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
      docker_registry_url = "https://docker.io"
      docker_image_name   = "enriquecatala/fastapi-helloworld:${local.docker_image_tag}"
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
# REGISTER BACKEND API DATABASE
# ===============================================================================

resource "azurerm_postgresql_server" "server-db" {
  name                = local.backend-app-db-server-name
  location            = "North Europe"
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "B_Gen5_2"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true

  administrator_login          = "agheventhubdbadmin"
  administrator_login_password = azurerm_key_vault_secret.db-admin-password.value

  version = "11"

  ssl_enforcement_enabled = true

  tags = {
    env = "${local.environment}"
  }
}

resource "azurerm_postgresql_database" "db" {
  name                = local.backend-app-db-name
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.server-db.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
}
