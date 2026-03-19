# subscription_id is intentionally omitted — set via TF_VAR_subscription_id
# in CI/CD (from AZURE_SUBSCRIPTION_ID secret) or locally via environment.
project           = "checkout"
environment       = "dev"
location          = "westeurope"
alert_email       = "platform-dev@checkout.com"
allowed_client_cn = "api-client.internal.checkout.com"

tags = {
  cost_center = "platform-engineering"
}
