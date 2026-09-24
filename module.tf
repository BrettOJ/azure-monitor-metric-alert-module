locals {
  duration_minutes = {
    PT1M  = 1
    PT5M  = 5
    PT15M = 15
    PT30M = 30
    PT1H  = 60
    PT6H  = 360
    PT12H = 720
    P1D   = 1440
  }

  requires_target_metadata = {
    for key, alert in var.metric_alerts : key => (
      length(alert.scopes) > 1 ||
      anytrue([
        for scope in alert.scopes :
        can(regex(
          "(?i)^/subscriptions/[^/]+(/resourcegroups/[^/]+)?/?$",
          scope
        ))
      ])
    )
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = var.metric_alerts

  name = each.value.name

  resource_group_name = coalesce(
    each.value.resource_group_name,
    var.resource_group_name
  )

  scopes                   = each.value.scopes
  description              = each.value.description
  enabled                  = each.value.enabled
  auto_mitigate             = each.value.auto_mitigate
  severity                 = each.value.severity
  frequency                = each.value.frequency
  window_size              = each.value.window_size
  target_resource_type     = each.value.target_resource_type
  target_resource_location = each.value.target_resource_location
  tags                     = merge(var.tags, each.value.tags)

  dynamic "criteria" {
    for_each = each.value.criteria
    iterator = criterion

    content {
      metric_namespace       = criterion.value.metric_namespace
      metric_name            = criterion.value.metric_name
      aggregation            = criterion.value.aggregation
      operator               = criterion.value.operator
      threshold              = criterion.value.threshold
      skip_metric_validation = criterion.value.skip_metric_validation

      dynamic "dimension" {
        for_each = criterion.value.dimensions
        iterator = dim

        content {
          name     = dim.value.name
          operator = dim.value.operator
          values   = dim.value.values
        }
      }
    }
  }

  dynamic "dynamic_criteria" {
    for_each = each.value.dynamic_criteria == null ? {} : {
      this = each.value.dynamic_criteria
    }
    iterator = criterion

    content {
      metric_namespace         = criterion.value.metric_namespace
      metric_name              = criterion.value.metric_name
      aggregation              = criterion.value.aggregation
      operator                 = criterion.value.operator
      alert_sensitivity        = criterion.value.alert_sensitivity
      evaluation_total_count   = criterion.value.evaluation_total_count
      evaluation_failure_count = criterion.value.evaluation_failure_count
      ignore_data_before       = criterion.value.ignore_data_before
      skip_metric_validation   = criterion.value.skip_metric_validation

      dynamic "dimension" {
        for_each = criterion.value.dimensions
        iterator = dim

        content {
          name     = dim.value.name
          operator = dim.value.operator
          values   = dim.value.values
        }
      }
    }
  }

  dynamic "application_insights_web_test_location_availability_criteria" {
    for_each = each.value.web_test_criteria == null ? {} : {
      this = each.value.web_test_criteria
    }
    iterator = web_test

    content {
      web_test_id           = web_test.value.web_test_resource_id
      component_id          = web_test.value.component_resource_id
      failed_location_count = web_test.value.failed_location_count
    }
  }

  dynamic "action" {
    for_each = each.value.actions
    iterator = alert_action

    content {
      action_group_id = (
        alert_action.value.action_group_key != null
        ? try(
          azurerm_monitor_action_group.this[
            alert_action.value.action_group_key
          ].id,
          null
        )
        : alert_action.value.action_group_resource_id
      )

      webhook_properties = alert_action.value.webhook_properties
    }
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for action in values(each.value.actions) :
        action.action_group_key == null ? true : (
          var.create_action_group &&
          contains(keys(var.action_groups), action.action_group_key)
        )
      ])
      error_message = "Alert '${each.key}' references an action group key that is undefined or creation is disabled."
    }

    precondition {
      condition = (
        lookup(local.duration_minutes, each.value.window_size, 0) >
        lookup(local.duration_minutes, each.value.frequency, 0)
      )
      error_message = "Alert '${each.key}' must have a window_size greater than frequency."
    }

    precondition {
      condition = !local.requires_target_metadata[each.key] || (
        try(
          length(trimspace(each.value.target_resource_type)) > 0,
          false
        ) &&
        try(
          length(trimspace(each.value.target_resource_location)) > 0,
          false
        )
      )
      error_message = "Alert '${each.key}' requires target_resource_type and target_resource_location for multiple, resource-group, or subscription scopes."
    }
  }
}