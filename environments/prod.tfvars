# subscription_id is intentionally omitted — set via TF_VAR_subscription_id
# in CI/CD (from AZURE_SUBSCRIPTION_ID secret) or locally via environment.
project           = "cko"
environment       = "prod"
location          = "uksouth"
alert_email       = "platform-oncall@checkout.com"
allowed_client_cn = "api-client.internal.checkout.com"

tags = {
  cost_center = "platform-engineering"
  compliance  = "pci-dss"
}
