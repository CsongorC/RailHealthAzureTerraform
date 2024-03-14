terraform {
  backend "azurerm" {
    resource_group_name  = "Rail-Health"
    storage_account_name = "storagerailhealth"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.94.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

locals {
  tag = "rail-health"
}

resource "azurerm_resource_group" "rgRailHealth" {
  name     = "Rail-Health"
  location = "Germany West Central"
  tags = {
        PROJECT = local.tag
  }
}

resource "azurerm_storage_account" "storageRailHealth" {
  name                     = "storagerailhealth"
  resource_group_name      = azurerm_resource_group.rgRailHealth.name
  location                 = azurerm_resource_group.rgRailHealth.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    PROJECT = local.tag
  }
}

resource "azurerm_storage_container" "containerTFState" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.storageRailHealth.name
  container_access_type = "private"
}
resource "azurerm_storage_container" "containerMearurements" {
  name                  = "measurements"
  storage_account_name  = azurerm_storage_account.storageRailHealth.name
  container_access_type = "private"
}

# resource "azurerm_kusto_cluster" "kcrailhealth" {
#   name                = "kcrailhealth"
#   location            = "West Europe"
#   resource_group_name = azurerm_resource_group.rgRailHealth.name
#   sku {
#     name     = "Dev(No SLA)_Standard_E2a_v4"
#     capacity = 1
#   }

#   zones = ["1", "3", "2"]

#   identity {
#     type = "SystemAssigned"
#   }

#   tags = {
#     PROJECT = local.tag
#   }

#   trusted_external_tenants = []
#   language_extensions      = []

# }
resource "azurerm_eventhub" "eventHubRailHealth" {
    name = "eventHubRailHealth"
    namespace_name = azurerm_eventhub_namespace.rail_health_event_hub_ns.name
    resource_group_name = azurerm_resource_group.rgRailHealth.name

    message_retention = 1
    partition_count = 2
    status = "Active"
    capture_description {
      enabled = true
      encoding = "Avro"
      destination {
        name = "EventHubArchive.AzureBlockBlob"
        archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
        blob_container_name = "measurements"
        storage_account_id = azurerm_storage_account.storageRailHealth.id
      }
      interval_in_seconds = 300
      size_limit_in_bytes = 314572800
    }
    depends_on = [azurerm_role_assignment.eventhub_storage_owner]
}

resource "azurerm_eventhub_namespace" "rail_health_event_hub_ns" {
  name                    = "eventHubNamespaceRailHealth"
  location                = "West Europe"
  resource_group_name     = azurerm_resource_group.rgRailHealth.name

  sku                     = "Standard"
  capacity                = 1

  zone_redundant          = true
  auto_inflate_enabled    = false
  maximum_throughput_units = 0

  identity {
    type = "SystemAssigned"
  }

  tags = {
    PROJECT = local.tag
  }
}

resource "azurerm_role_assignment" "eventhub_storage_owner" {
  scope                = azurerm_storage_account.storageRailHealth.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_eventhub_namespace.rail_health_event_hub_ns.identity[0].principal_id
}


resource "azurerm_eventhub_consumer_group" "rail_telemetry_default_consumer_group" {
    name                = "Default"
    eventhub_name       = azurerm_eventhub.eventHubRailHealth.name
    namespace_name      = azurerm_eventhub_namespace.rail_health_event_hub_ns.name
    resource_group_name = azurerm_resource_group.rgRailHealth.name
}

resource "azurerm_eventhub_consumer_group" "rail_telemetry_adx_consumer_group" {
    name                = "adx"
    eventhub_name       = azurerm_eventhub.eventHubRailHealth.name
    namespace_name      = azurerm_eventhub_namespace.rail_health_event_hub_ns.name
    resource_group_name = azurerm_resource_group.rgRailHealth.name
}

resource "azurerm_network_security_group" "rail_health_event_hub_ns_nsg" {
    name                = "eventHubNamespaceRailHealthNSG"
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.rgRailHealth.name

    tags = {
      PROJECT = local.tag
    } 
}