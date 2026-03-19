// Package main implements a smoke test Azure Function that validates the main
// API function end-to-end from inside the VNet, including mTLS authentication.
//
// Architecture:
//
//	GitHub Runner (public internet)
//	  → az functionapp function call (ARM control plane)
//	    → Smoke Test Function (test subnet, VNet-integrated)
//	      → HTTPS + client cert → Main Function (private endpoint)
//	        → Validates mTLS, processes request
//	      → Returns pass/fail with diagnostics
//	  → GitHub Runner reads result
package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/security/keyvault/azcertificates"
	"github.com/Azure/azure-sdk-for-go/sdk/security/keyvault/azsecrets"
)

const (
	listenAddr       = ":8080"
	requestTimeout   = 30 * time.Second
	certName         = "api-client-cert"
	maxResponseBytes = 1 << 20 // 1 MB
)

// TestResult captures the smoke test outcome.
type TestResult struct {
	Status       string            `json:"status"` // "pass" or "fail"
	Tests        []TestCase        `json:"tests"`
	Duration     string            `json:"duration"`
	TargetURL    string            `json:"target_url"`
	Error        string            `json:"error,omitempty"`
	Connectivity map[string]string `json:"connectivity"`
}

// TestCase represents a single test assertion.
type TestCase struct {
	Name   string `json:"name"`
	Passed bool   `json:"passed"`
	Detail string `json:"detail,omitempty"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/smoketest", handleSmokeTest)

	addr := listenAddr
	if port := os.Getenv("FUNCTIONS_CUSTOMHANDLER_PORT"); port != "" {
		addr = ":" + port
	}

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("Smoke test function starting on %s", addr) //nolint:gosec // G706: addr is from FUNCTIONS_CUSTOMHANDLER_PORT, set by Azure runtime — not user-controlled
	log.Fatal(srv.ListenAndServe())
}

func handleSmokeTest(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	w.Header().Set("Content-Type", "application/json")

	result := TestResult{
		Status:       "pass",
		Tests:        []TestCase{},
		Connectivity: map[string]string{},
	}

	// Get configuration from environment
	targetHost := os.Getenv("TARGET_FUNCTION_HOSTNAME")
	keyVaultURI := os.Getenv("KEY_VAULT_URI")

	if targetHost == "" || keyVaultURI == "" {
		result.Status = "fail"
		result.Error = "TARGET_FUNCTION_HOSTNAME and KEY_VAULT_URI must be set"
		writeResult(w, result, start)
		return
	}

	targetURL := fmt.Sprintf("https://%s/api/message", targetHost)
	result.TargetURL = targetURL

	// --- Test 1: Fetch client certificate from Key Vault ---
	tlsConfig, err := fetchClientCert(r.Context(), keyVaultURI)
	if err != nil {
		result.Tests = append(result.Tests, TestCase{
			Name:   "key_vault_cert_fetch",
			Passed: false,
			Detail: fmt.Sprintf("Failed to fetch client cert: %v", err),
		})
		result.Status = "fail"
		writeResult(w, result, start)
		return
	}
	result.Tests = append(result.Tests, TestCase{
		Name:   "key_vault_cert_fetch",
		Passed: true,
		Detail: "Successfully fetched client certificate from Key Vault via Managed Identity",
	})
	result.Connectivity["key_vault"] = "ok"

	// --- Test 2: POST /api/message with mTLS ---
	client := &http.Client{
		Timeout: requestTimeout,
		Transport: &http.Transport{
			TLSClientConfig: tlsConfig,
		},
	}

	payload := map[string]string{"message": "smoke-test-probe"}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, targetURL, bytes.NewReader(body)) //nolint:gosec // G704: targetURL is from a trusted env var (TARGET_FUNCTION_HOSTNAME), not user input
	if err != nil {
		result.Tests = append(result.Tests, TestCase{
			Name:   "mtls_api_call",
			Passed: false,
			Detail: fmt.Sprintf("Failed to create request: %v", err),
		})
		result.Status = "fail"
		writeResult(w, result, start)
		return
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req) //nolint:gosec // G704: request URL from trusted env var, not user input
	if err != nil {
		result.Tests = append(result.Tests, TestCase{
			Name:   "mtls_api_call",
			Passed: false,
			Detail: fmt.Sprintf("Request failed: %v", err),
		})
		result.Status = "fail"
		result.Connectivity["main_function"] = fmt.Sprintf("error: %v", err)
		writeResult(w, result, start)
		return
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))

	// --- Test 3: Status code check ---
	result.Tests = append(result.Tests, TestCase{
		Name:   "http_status_200",
		Passed: resp.StatusCode == http.StatusOK,
		Detail: fmt.Sprintf("Got status %d, body: %s", resp.StatusCode, string(respBody)),
	})
	if resp.StatusCode != http.StatusOK {
		result.Status = "fail"
	}
	result.Connectivity["main_function"] = fmt.Sprintf("status_%d", resp.StatusCode)

	// --- Test 4: Response body validation ---
	var apiResp struct {
		Message   string `json:"message"`
		Timestamp string `json:"timestamp"`
		RequestID string `json:"request_id"`
	}
	if err := json.Unmarshal(respBody, &apiResp); err != nil {
		result.Tests = append(result.Tests, TestCase{
			Name:   "response_body_valid",
			Passed: false,
			Detail: fmt.Sprintf("Failed to parse response JSON: %v", err),
		})
		result.Status = "fail"
	} else {
		bodyValid := apiResp.Message == "smoke-test-probe" &&
			apiResp.Timestamp != "" &&
			apiResp.RequestID != ""
		result.Tests = append(result.Tests, TestCase{
			Name:   "response_body_valid",
			Passed: bodyValid,
			Detail: fmt.Sprintf("message=%q, timestamp=%q, request_id=%q", apiResp.Message, apiResp.Timestamp, apiResp.RequestID),
		})
		if !bodyValid {
			result.Status = "fail"
		}
	}

	// --- Test 5: Request-ID header present ---
	reqID := resp.Header.Get("X-Request-ID")
	result.Tests = append(result.Tests, TestCase{
		Name:   "request_id_header",
		Passed: reqID != "",
		Detail: fmt.Sprintf("X-Request-ID: %s", reqID),
	})
	if reqID == "" {
		result.Status = "fail"
	}

	writeResult(w, result, start)
}

// fetchClientCert retrieves the client certificate and private key from Key Vault
// using Managed Identity, and returns a TLS config for mTLS connections.
func fetchClientCert(ctx context.Context, vaultURI string) (*tls.Config, error) {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create credential: %w", err)
	}

	// Fetch the certificate (public part)
	certClient, err := azcertificates.NewClient(vaultURI, cred, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create cert client: %w", err)
	}

	certResp, err := certClient.GetCertificate(ctx, certName, "", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get certificate: %w", err)
	}

	// Fetch the private key (stored as a secret with same name)
	secretClient, err := azsecrets.NewClient(vaultURI, cred, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create secret client: %w", err)
	}

	secretResp, err := secretClient.GetSecret(ctx, certName, "", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to get private key secret: %w", err)
	}

	// Parse PEM-encoded cert and key from the secret value
	// Azure Key Vault stores the full PFX/PEM bundle in the secret
	pemData := []byte(*secretResp.Value)

	var certPEMBlocks []byte
	var keyPEMBlock []byte

	for {
		var block *pem.Block
		block, pemData = pem.Decode(pemData)
		if block == nil {
			break
		}
		switch block.Type {
		case "CERTIFICATE":
			certPEMBlocks = append(certPEMBlocks, pem.EncodeToMemory(block)...)
		case "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY":
			keyPEMBlock = pem.EncodeToMemory(block)
		}
	}

	if len(certPEMBlocks) == 0 {
		// Certificate might be DER-encoded in the cert response
		certPEMBlocks = pem.EncodeToMemory(&pem.Block{
			Type:  "CERTIFICATE",
			Bytes: certResp.CER,
		})
	}

	if keyPEMBlock == nil {
		return nil, fmt.Errorf("no private key found in Key Vault secret")
	}

	tlsCert, err := tls.X509KeyPair(certPEMBlocks, keyPEMBlock)
	if err != nil {
		return nil, fmt.Errorf("failed to create TLS key pair: %w", err)
	}

	// Build CA pool from the cert chain for server verification
	// For self-signed certs, we skip server verification (InsecureSkipVerify)
	// since the Function App uses Azure-managed TLS, not our self-signed CA
	return &tls.Config{
		Certificates:       []tls.Certificate{tlsCert},
		InsecureSkipVerify: true, //nolint:gosec // G402: Azure Function App uses platform-managed TLS cert, not our self-signed CA
		MinVersion:         tls.VersionTLS12,
	}, nil
}

func writeResult(w http.ResponseWriter, result TestResult, start time.Time) {
	result.Duration = time.Since(start).String()

	status := http.StatusOK
	if result.Status == "fail" {
		status = http.StatusServiceUnavailable
	}

	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(result); err != nil {
		log.Printf("Failed to encode result: %v", err)
	}
}
