terraform {
  backend "azurerm" {
    resource_group_name  = "Rail-Health"         # Azure resource group for storing Terraform state
    storage_account_name = "storagerailhealth"   # Storage account for storing Terraform state
    container_name       = "tfstate"             # Container within the storage account for storing Terraform state
    key                  = "terraform.tfstate"   # Name of the Terraform state file
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"             # Source of Azure provider
      version = "=3.94.0"                       # Version of Azure provider
    }
  }
}

provider "azurerm" {
  features {}                                  # Optional provider features
  skip_provider_registration = true            # Skip provider registration during initialization
}

locals {
  tag = "rail-health"                          # Local variable for project tag
}

# Azure resource group for Rail Health project
resource "azurerm_resource_group" "rgRailHealth" {
  name     = "Rail-Health"                     # Name of the resource group
  location = "Germany West Central"            # Location of the resource group
  tags = {
        PROJECT = local.tag                    # Tags for the resource group
  }
}

# Azure storage account for Rail Health project
resource "azurerm_storage_account" "storageRailHealth" {
  name                     = "storagerailhealth"                           # Name of the storage account
  resource_group_name      = azurerm_resource_group.rgRailHealth.name      # Resource group name
  location                 = azurerm_resource_group.rgRailHealth.location  # Location
  account_tier             = "Standard"                                    # Storage account tier
  account_replication_type = "LRS"                                         # Replication type

  tags = {
    PROJECT = local.tag  # Tags for the storage account
  }
}

# Azure storage container for storing Terraform state
resource "azurerm_storage_container" "containerTFState" {
  name                  = "tfstate"                                         # Name of the container
  storage_account_name  = azurerm_storage_account.storageRailHealth.name    # Name of the storage account
  container_access_type = "private"                                         # Access type for the container
}

# Azure storage container for storing measurements
resource "azurerm_storage_container" "containerMeasurements" {
  name                  = "measurements"                                    # Name of the container
  storage_account_name  = azurerm_storage_account.storageRailHealth.name    # Name of the storage account
  container_access_type = "private"                                         # Access type for the container
}

# Azure Kusto cluster for Rail Health project
resource "azurerm_kusto_cluster" "kcrailhealth" {
  name                = "kcrailhealth"                                      # Name of the Kusto cluster
  location            = "West Europe"                                       # Location of the cluster
  resource_group_name = azurerm_resource_group.rgRailHealth.name            # Resource group name

  sku {                                                                     # SKU details for the cluster
    name     = "Dev(No SLA)_Standard_E2a_v4"                                # SKU name
    capacity = 1                                                            # Capacity
  }

  zones = ["1", "3", "2"]                                                   # Availability zones, default values

  identity {                                                                # Identity configuration
    type = "SystemAssigned"                                                 # Identity type
  }

  tags = {                                                                  # Tags for the Kusto cluster
    PROJECT = local.tag                                                      
  }

  trusted_external_tenants = []                                             # List of trusted external tenants
  language_extensions      = []                                             # List of language extensions
}

# Azure Event Hub for Rail Health project
resource "azurerm_eventhub" "eventHubRailHealth" {
    name = "eventHubRailHealth"                                                # Name of the Event Hub
    namespace_name = azurerm_eventhub_namespace.rail_health_event_hub_ns.name  # Name of the Event Hub namespace
    resource_group_name = azurerm_resource_group.rgRailHealth.name             # Resource group name

    message_retention = 1                                                      # Message retention period
    partition_count = 2                                                        # Number of partitions
    status = "Active"                                                          # Status of the Event Hub

    capture_description {                                                      # Capture configuration
      enabled = true                                                           # Whether capture is enabled
      encoding = "Avro"                                                        # Encoding format
      destination {                                                            # Capture destination
        name = "EventHubArchive.AzureBlockBlob"                                # Destination name
        archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"  # Archive name format
        blob_container_name = "measurements"                                   # Container name for captured data
        storage_account_id = azurerm_storage_account.storageRailHealth.id      # Storage account ID
      }
      interval_in_seconds = 300                                                # Capture interval in seconds
      size_limit_in_bytes = 314572800                                          # Size limit for captured data
    }

    depends_on = [azurerm_role_assignment.eventhub_storage_owner]              # Dependencies
}

# Azure Event Hub namespace for Rail Health project
resource "azurerm_eventhub_namespace" "rail_health_event_hub_ns" {
  name                    = "eventHubNamespaceRailHealth"                     # Name of the Event Hub namespace
  location                = "West Europe"                                     # Location of the namespace
  resource_group_name     = azurerm_resource_group.rgRailHealth.name          # Resource group name

  sku                     = "Standard"                                        # SKU for the namespace
  capacity                = 1                                                 # Capacity of the namespace

  zone_redundant          = true                                              # Whether zone redundancy is enabled
  auto_inflate_enabled    = false                                             # Whether auto inflation is enabled
  maximum_throughput_units = 0                                                # Maximum throughput units

  identity {                                                                  # Identity configuration
    type = "SystemAssigned"                                                   # Identity type
  }

  tags = {                                                                    # Tags for the namespace
    PROJECT = local.tag                                                      
  }
}

# Azure role assignment for Event Hub storage owner
resource "azurerm_role_assignment" "eventhub_storage_owner" {
  scope                = azurerm_storage_account.storageRailHealth.id         # Scope of the role assignment
  role_definition_name = "Storage Blob Data Owner"                            # Name of the role definition
  principal_id         = azurerm_eventhub_namespace.rail_health_event_hub_ns.identity[0].principal_id  # Principal ID
}



# Azure Event Hub consumer group for Rail Health project (default)
resource "azurerm_eventhub_consumer_group" "rail_telemetry_default_consumer_group" {
    name                = "Default"                                                           # Name of the consumer group
    eventhub_name       = azurerm_eventhub.eventHubRailHealth.name                            # Name of the Event Hub
    namespace_name      = azurerm_eventhub_namespace.rail_health_event_hub_ns.name            # Name of the Event Hub namespace
    resource_group_name = azurerm_resource_group.rgRailHealth.name                            # Resource group name
}

# Azure Event Hub consumer group for Rail Health project (ADX)
resource "azurerm_eventhub_consumer_group" "rail_telemetry_adx_consumer_group" {
    name                = "adx"                                                               # Name of the consumer group
    eventhub_name       = azurerm_eventhub.eventHubRailHealth.name                            # Name of the Event Hub
    namespace_name      = azurerm_eventhub_namespace.rail_health_event_hub_ns.name            # Name of the Event Hub namespace
    resource_group_name = azurerm_resource_group.rgRailHealth.name                            # Resource group name
}

# Azure network security group for Event Hub namespace
resource "azurerm_network_security_group" "rail_health_event_hub_ns_nsg" {
    name                = "eventHubNamespaceRailHealthNSG"                                    # Name of the network security group
    location            = "westeurope"                                                        # Location of the network security group
    resource_group_name = azurerm_resource_group.rgRailHealth.name                            # Resource group name

    tags = {                                                                                  # Tags for the network security group
      PROJECT = local.tag
    } 
}

# Azure Kusto database for Rail Health project
resource "azurerm_kusto_database" "rail_health_database" {
  name = "rail-health-database"                                                               # Name of the Kusto database
  resource_group_name = azurerm_resource_group.rgRailHealth.name                              # Resource group name
  location            = azurerm_kusto_cluster.kcrailhealth.location                           # Location of the Kusto database
  cluster_name        = azurerm_kusto_cluster.kcrailhealth.name                               # Name of the Kusto cluster
  hot_cache_period    = "P7D"                                                                 # Hot cache period
  soft_delete_period  = "P31D"                                                                # Soft delete period
}

# Azure Kusto Cluster - Event Hub data connection for Rail Health project 
resource "azurerm_kusto_eventhub_data_connection" "eventhub_connection" {
  name                = "rail-health-eventhub-data-connection"                                   # Name of the data connection
  resource_group_name = azurerm_resource_group.rgRailHealth.name                                 # Resource group name
  location            = azurerm_kusto_cluster.kcrailhealth.location                              # Location of the data connection
  cluster_name        = azurerm_kusto_cluster.kcrailhealth.name                                  # Name of the Kusto cluster
  database_name       = azurerm_kusto_database.rail_health_database.name                         # Name of the Kusto database

  table_name          = "measurement"                                                            # Name of the table
  mapping_rule_name   = "measurement_mapping"                                                    # Name of the mapping rule
  data_format         = "MULTIJSON"                                                              # Data format

  eventhub_id         = azurerm_eventhub.eventHubRailHealth.id                                   # ID of the Event Hub
  consumer_group      = azurerm_eventhub_consumer_group.rail_telemetry_adx_consumer_group.name   # Name of the consumer group
}
