resource "azurerm_api_management" "main" {
  name                 = "apim-${var.name_prefix}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  publisher_name       = var.publisher_name
  publisher_email      = var.publisher_email
  sku_name             = "Developer_1"
  virtual_network_type = "Internal"
  # Note: public_network_access cannot be disabled during initial creation
  # (Azure API limitation: ActivateServiceWithPrivateEndpointAccessNotAllowed).
  # Disable it in a subsequent apply or via az cli post-provisioning.
  public_network_access_enabled = true
  tags                          = var.tags

  virtual_network_configuration {
    subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }
}

# --- Post-provisioning stabilisation ---
# Azure APIM Developer tier takes ~28 minutes to provision. When it completes,
# Azure's internal async processes (diagnostic settings, internal certificates,
# DNS registration) continue running in the background. If Terraform immediately
# creates child resources (certificates, APIs, diagnostics), they collide with
# Azure's internal creation and fail with "already exists" errors.
#
# This is a known azurerm provider issue:
# https://github.com/hashicorp/terraform-provider-azurerm/issues/24135
#
# The time_sleep gives Azure 60 seconds to finish its internal housekeeping
# before we create any child resources. All APIM child resources depend on this.

resource "time_sleep" "wait_for_apim_internals" {
  depends_on      = [azurerm_api_management.main]
  create_duration = "60s"
}

# --- CA Certificate for mTLS ---

resource "azurerm_api_management_certificate" "ca" {
  depends_on          = [time_sleep.wait_for_apim_internals]
  name                = "internal-ca"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  data                = base64encode(var.ca_cert_pem)
}

# --- API Definition ---

resource "azurerm_api_management_api" "message" {
  depends_on            = [time_sleep.wait_for_apim_internals]
  name                  = "message-api"
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = var.resource_group_name
  revision              = "1"
  display_name          = "Message API"
  path                  = "api"
  protocols             = ["https"]
  subscription_required = false

  service_url = "https://${var.function_app_hostname}"
}

resource "azurerm_api_management_api_operation" "post_message" {
  operation_id        = "post-message"
  api_name            = azurerm_api_management_api.message.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Post Message"
  method              = "POST"
  url_template        = "/message"

  response {
    status_code = 200
  }
}

# --- mTLS Policy ---
# Validates client certificates at the APIM gateway level.
# Checks: issuer, subject CN, and that the cert is not expired.

resource "azurerm_api_management_api_policy" "message_mtls" {
  api_name            = azurerm_api_management_api.message.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <validate-client-certificate
          validate-revocation="false"
          validate-trust="false"
          validate-not-before="true"
          validate-not-after="true"
          ignore-error="false">
          <identities>
            <identity
              common-name="${var.allowed_client_cn}"
              issuer-certificate-id="${azurerm_api_management_certificate.ca.name}" />
          </identities>
        </validate-client-certificate>
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}
