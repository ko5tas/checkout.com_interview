#!/usr/bin/env bash
#
# Demo script for testing the internal API via mTLS.
#
# Usage (from within the VNet, e.g. bastion/jumpbox):
#   ./scripts/test-api.sh <APIM_GATEWAY_URL> <CLIENT_CERT_PATH> <CLIENT_KEY_PATH> <CA_CERT_PATH>
#
# Example:
#   ./scripts/test-api.sh https://apim-checkout-dev.azure-api.net \
#     ./certs/client.pem ./certs/client-key.pem ./certs/ca.pem

set -euo pipefail

GATEWAY_URL="${1:?Usage: $0 <gateway_url> <client_cert> <client_key> <ca_cert>}"
CLIENT_CERT="${2:?Missing client certificate path}"
CLIENT_KEY="${3:?Missing client key path}"
CA_CERT="${4:?Missing CA certificate path}"

API_ENDPOINT="${GATEWAY_URL}/api/message"

echo "=== Internal API mTLS Demo ==="
echo "Endpoint: ${API_ENDPOINT}"
echo ""

# Test 1: Valid request
echo "--- Test 1: Valid POST request ---"
curl -s -w "\nHTTP Status: %{http_code}\n" \
  --cert "${CLIENT_CERT}" \
  --key "${CLIENT_KEY}" \
  --cacert "${CA_CERT}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello from the platform team!"}' \
  "${API_ENDPOINT}" | jq . 2>/dev/null || true
echo ""

# Test 2: Missing message field
echo "--- Test 2: Missing message field ---"
curl -s -w "\nHTTP Status: %{http_code}\n" \
  --cert "${CLIENT_CERT}" \
  --key "${CLIENT_KEY}" \
  --cacert "${CA_CERT}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{}' \
  "${API_ENDPOINT}" | jq . 2>/dev/null || true
echo ""

# Test 3: Invalid JSON
echo "--- Test 3: Invalid JSON ---"
curl -s -w "\nHTTP Status: %{http_code}\n" \
  --cert "${CLIENT_CERT}" \
  --key "${CLIENT_KEY}" \
  --cacert "${CA_CERT}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d 'not json' \
  "${API_ENDPOINT}" | jq . 2>/dev/null || true
echo ""

# Test 4: Wrong HTTP method
echo "--- Test 4: GET instead of POST ---"
curl -s -w "\nHTTP Status: %{http_code}\n" \
  --cert "${CLIENT_CERT}" \
  --key "${CLIENT_KEY}" \
  --cacert "${CA_CERT}" \
  -X GET \
  "${API_ENDPOINT}" | jq . 2>/dev/null || true
echo ""

# Test 5: Unknown fields (strict schema)
echo "--- Test 5: Unknown fields in payload ---"
curl -s -w "\nHTTP Status: %{http_code}\n" \
  --cert "${CLIENT_CERT}" \
  --key "${CLIENT_KEY}" \
  --cacert "${CA_CERT}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"message":"test","extra":"should be rejected"}' \
  "${API_ENDPOINT}" | jq . 2>/dev/null || true
echo ""

echo "=== Demo Complete ==="
