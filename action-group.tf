resource "azurerm_monitor_action_group" "this" {
  for_each = var.create_action_group ? var.action_groups : {}

  name = each.value.name

  resource_group_name = coalesce(
    each.value.resource_group_name,
    var.resource_group_name
  )

  short_name = each.value.short_name
  location   = each.value.location
  enabled    = each.value.enabled
  tags       = merge(var.tags, each.value.tags)

  dynamic "email_receiver" {
    for_each = each.value.email_receivers
    iterator = receiver

    content {
      name                    = receiver.value.name
      email_address           = receiver.value.email_address
      use_common_alert_schema = receiver.value.use_common_alert_schema
    }
  }

  dynamic "sms_receiver" {
    for_each = each.value.sms_receivers
    iterator = receiver

    content {
      name         = receiver.value.name
      country_code = receiver.value.country_code
      phone_number = receiver.value.phone_number
    }
  }

  dynamic "webhook_receiver" {
    for_each = each.value.webhook_receivers
    iterator = receiver

    content {
      name                    = receiver.value.name
      service_uri             = receiver.value.service_uri
      use_common_alert_schema = receiver.value.use_common_alert_schema

      dynamic "aad_auth" {
        for_each = receiver.value.aad_auth == null ? {} : {
          this = receiver.value.aad_auth
        }
        iterator = auth

        content {
          object_id      = auth.value.object_id
          identifier_uri = auth.value.identifier_uri
          tenant_id      = auth.value.tenant_id
        }
      }
    }
  }
}