variable "resource_group_name" {
  type        = string
  description = "Default existing resource group for alerts and action groups."
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Default tags. Individual resource tags take precedence."
  nullable    = false
}

variable "create_action_group" {
  type        = bool
  default     = false
  description = "Whether to create the action groups defined in action_groups."
  nullable    = false
}

variable "action_groups" {
  type = map(object({
    name                = string
    short_name          = string
    resource_group_name = optional(string)
    location            = optional(string, "global")
    enabled             = optional(bool, true)
    tags                = optional(map(string), {})

    email_receivers = optional(map(object({
      name                    = string
      email_address           = string
      use_common_alert_schema = optional(bool, true)
    })), {})

    sms_receivers = optional(map(object({
      name         = string
      country_code = string
      phone_number = string
    })), {})

    webhook_receivers = optional(map(object({
      name                    = string
      service_uri             = string
      use_common_alert_schema = optional(bool, true)

      aad_auth = optional(object({
        object_id      = string
        identifier_uri = optional(string)
        tenant_id      = optional(string)
      }))
    })), {})
  }))

  default     = {}
  description = "Action groups keyed by stable logical names. Ignored when create_action_group is false."
  nullable    = false

  validation {
    condition = alltrue([
      for group in values(var.action_groups) :
      length(group.short_name) >= 1 && length(group.short_name) <= 12
    ])
    error_message = "Each action group short_name must contain 1 to 12 characters."
  }
}

variable "metric_alerts" {
  type = map(object({
    name                     = string
    scopes                   = set(string)
    resource_group_name      = optional(string)
    description              = optional(string)
    enabled                  = optional(bool, true)
    auto_mitigate            = optional(bool, true)
    severity                 = optional(number, 3)
    frequency                = optional(string, "PT1M")
    window_size              = optional(string, "PT5M")
    target_resource_type     = optional(string)
    target_resource_location = optional(string)
    tags                     = optional(map(string), {})

    criteria = optional(map(object({
      metric_namespace       = string
      metric_name            = string
      aggregation            = string
      operator               = string
      threshold              = number
      skip_metric_validation = optional(bool, false)

      dimensions = optional(map(object({
        name     = string
        operator = optional(string, "Include")
        values   = set(string)
      })), {})
    })), {})

    dynamic_criteria = optional(object({
      metric_namespace         = string
      metric_name              = string
      aggregation              = string
      operator                 = string
      alert_sensitivity        = optional(string, "Medium")
      evaluation_total_count   = optional(number, 4)
      evaluation_failure_count = optional(number, 4)
      ignore_data_before       = optional(string)
      skip_metric_validation   = optional(bool, false)

      dimensions = optional(map(object({
        name     = string
        operator = optional(string, "Include")
        values   = set(string)
      })), {})
    }))

    web_test_criteria = optional(object({
      web_test_resource_id   = string
      component_resource_id  = string
      failed_location_count = number
    }))

    actions = optional(map(object({
      # Supply exactly one of these two attributes.
      action_group_key         = optional(string)
      action_group_resource_id = optional(string)
      webhook_properties       = optional(map(string), {})
    })), {})
  }))

  default     = {}
  description = "Metric alerts keyed by stable logical names."
  nullable    = false

  validation {
    condition = alltrue([
      for alert in values(var.metric_alerts) :
      length(alert.scopes) > 0 &&
      contains([0, 1, 2, 3, 4], alert.severity)
    ])
    error_message = "Every alert must have at least one scope and an integer severity from 0 to 4."
  }

  validation {
    condition = alltrue([
      for alert in values(var.metric_alerts) :
      (
        (length(alert.criteria) > 0 ? 1 : 0) +
        (alert.dynamic_criteria != null ? 1 : 0) +
        (alert.web_test_criteria != null ? 1 : 0)
      ) == 1
    ])
    error_message = "Every alert must define exactly one of criteria, dynamic_criteria, or web_test_criteria."
  }

  validation {
    condition = alltrue(flatten([
      for alert in values(var.metric_alerts) : [
        for action in values(alert.actions) :
        (action.action_group_key != null) !=
        (action.action_group_resource_id != null)
      ]
    ]))
    error_message = "Each action must specify exactly one of action_group_key or action_group_resource_id."
  }

  validation {
    condition = alltrue([
      for alert in values(var.metric_alerts) :
      contains(
        ["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"],
        alert.frequency
      ) &&
      contains(
        ["PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "P1D"],
        alert.window_size
      )
    ])
    error_message = "Each alert must use supported frequency and window_size durations."
  }

  validation {
    condition = alltrue(flatten([
      for alert in values(var.metric_alerts) : [
        for criterion in values(alert.criteria) :
        contains(
          ["Average", "Count", "Minimum", "Maximum", "Total"],
          criterion.aggregation
        ) &&
        contains(
          ["Equals", "GreaterThan", "GreaterThanOrEqual", "LessThan", "LessThanOrEqual"],
          criterion.operator
        )
      ]
    ]))
    error_message = "Static criteria must use supported aggregations and operators."
  }

  validation {
    condition = alltrue([
      for alert in values(var.metric_alerts) :
      alert.dynamic_criteria == null ? true : (
        contains(
          ["Average", "Count", "Minimum", "Maximum", "Total"],
          alert.dynamic_criteria.aggregation
        ) &&
        contains(
          ["LessThan", "GreaterThan", "GreaterOrLessThan"],
          alert.dynamic_criteria.operator
        ) &&
        contains(
          ["Low", "Medium", "High"],
          alert.dynamic_criteria.alert_sensitivity
        ) &&
        alert.dynamic_criteria.evaluation_failure_count >= 1 &&
        alert.dynamic_criteria.evaluation_failure_count <=
        alert.dynamic_criteria.evaluation_total_count &&
        floor(alert.dynamic_criteria.evaluation_failure_count) ==
        alert.dynamic_criteria.evaluation_failure_count &&
        floor(alert.dynamic_criteria.evaluation_total_count) ==
        alert.dynamic_criteria.evaluation_total_count
      )
    ])
    error_message = "Dynamic criteria must use supported settings and positive integer evaluation counts; failures cannot exceed total evaluations."
  }

  validation {
    condition = alltrue([
      for alert in values(var.metric_alerts) :
      alert.web_test_criteria == null ? true : (
        alert.web_test_criteria.failed_location_count >= 1 &&
        floor(alert.web_test_criteria.failed_location_count) ==
        alert.web_test_criteria.failed_location_count
      )
    ])
    error_message = "Web-test failed_location_count must be a positive integer."
  }
}