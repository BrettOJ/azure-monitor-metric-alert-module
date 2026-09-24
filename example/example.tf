module "monitoring" {
  source = "./modules/metric-alert"

  resource_group_name = azurerm_resource_group.monitoring.name
  create_action_group = true

  tags = {
    environment = "production"
    managed_by  = "terraform"
  }

  action_groups = {
    operations = {
      name       = "ag-operations"
      short_name = "ops"

      email_receivers = {
        operations_email = {
          name          = "operations-email"
          email_address = "operations@example.com"
        }
      }
    }

    platform = {
      name       = "ag-platform"
      short_name = "platform"

      email_receivers = {
        platform_email = {
          name          = "platform-email"
          email_address = "platform@example.com"
        }
      }
    }
  }

  metric_alerts = {
    vm_cpu = {
      name        = "alert-vm-high-cpu"
      description = "Average CPU exceeds 80 percent."
      scopes      = [azurerm_linux_virtual_machine.app.id]
      severity    = 2
      frequency   = "PT1M"
      window_size = "PT5M"

      criteria = {
        cpu = {
          metric_namespace = "Microsoft.Compute/virtualMachines"
          metric_name      = "Percentage CPU"
          aggregation      = "Average"
          operator         = "GreaterThan"
          threshold        = 80
        }
      }

      actions = {
        operations = {
          action_group_key = "operations"
        }

        existing_service_desk = {
          action_group_resource_id = var.existing_action_group_resource_id
        }
      }
    }

    storage_transactions = {
      name        = "alert-storage-transactions"
      description = "Storage transactions exceed the learned threshold."
      scopes      = [azurerm_storage_account.app.id]
      severity    = 3
      frequency   = "PT5M"
      window_size = "PT15M"

      dynamic_criteria = {
        metric_namespace         = "Microsoft.Storage/storageAccounts"
        metric_name              = "Transactions"
        aggregation              = "Total"
        operator                 = "GreaterThan"
        alert_sensitivity        = "Medium"
        evaluation_total_count   = 4
        evaluation_failure_count = 3

        dimensions = {
          api = {
            name   = "ApiName"
            values = ["*"]
          }
        }
      }

      actions = {
        platform = {
          action_group_key = "platform"
        }
      }
    }
  }
}

output "cpu_alert_id" {
  value = module.monitoring.metric_alert_resource_ids["vm_cpu"]
}

output "operations_action_group_id" {
  value = module.monitoring.action_group_resource_ids["operations"]
}