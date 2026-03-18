subscription_id   = "" # Set via environment or CI/CD
project           = "checkout"
environment       = "prod"
location          = "uksouth"
alert_email       = "platform-oncall@checkout.com"
allowed_client_cn = "api-client.internal.checkout.com"

tags = {
  cost_center = "platform-engineering"
  compliance  = "pci-dss"
}
