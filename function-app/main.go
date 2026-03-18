package main

import (
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
)

const (
	maxPayloadSize = 1 << 20 // 1 MB
	maxMessageLen  = 10000
	listenAddr     = ":8080"
)

// MessageRequest is the expected request payload.
type MessageRequest struct {
	Message string `json:"message"`
}

// MessageResponse is the API response payload.
type MessageResponse struct {
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
	RequestID string `json:"request_id"`
}

// ErrorResponse is the error response payload.
type ErrorResponse struct {
	Error     string `json:"error"`
	RequestID string `json:"request_id"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/message", handleMessage)

	addr := listenAddr
	port := os.Getenv("FUNCTIONS_CUSTOMHANDLER_PORT")
	if port != "" {
		addr = ":" + port
	}

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("Starting server on %s", addr) //nolint:gosec // G706: addr is from FUNCTIONS_CUSTOMHANDLER_PORT, set by Azure runtime — not user-controlled
	log.Fatal(srv.ListenAndServe())
}

func handleMessage(w http.ResponseWriter, r *http.Request) {
	requestID := uuid.New().String()
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Request-ID", requestID)

	// Method check
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed", requestID)
		return
	}

	// Content-Type check
	ct := r.Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "application/json") {
		writeError(w, http.StatusUnsupportedMediaType, "content-type must be application/json", requestID)
		return
	}

	// Client certificate validation (defense-in-depth)
	if err := validateClientCert(r); err != nil {
		log.Printf("[%s] client cert validation failed: %v", requestID, err)
		writeError(w, http.StatusForbidden, "client certificate validation failed", requestID)
		return
	}

	// Read body with size limit
	body, err := io.ReadAll(io.LimitReader(r.Body, maxPayloadSize+1))
	if err != nil {
		writeError(w, http.StatusBadRequest, "failed to read request body", requestID)
		return
	}
	if len(body) > maxPayloadSize {
		writeError(w, http.StatusRequestEntityTooLarge, "payload exceeds maximum size", requestID)
		return
	}

	// Parse JSON
	var req MessageRequest
	decoder := json.NewDecoder(strings.NewReader(string(body)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("invalid JSON: %v", err), requestID)
		return
	}

	// Validate message field
	if req.Message == "" {
		writeError(w, http.StatusBadRequest, "message field is required and must be non-empty", requestID)
		return
	}
	if len(req.Message) > maxMessageLen {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("message exceeds maximum length of %d characters", maxMessageLen), requestID)
		return
	}

	// Success response
	resp := MessageResponse{
		Message:   req.Message,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		RequestID: requestID,
	}

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("[%s] failed to encode response: %v", requestID, err)
	}
}

// validateClientCert checks the X-ARR-ClientCert header (set by Azure App Service
// when client_certificate_mode = "Required"). In local/test mode, this is a no-op.
func validateClientCert(r *http.Request) error {
	certHeader := r.Header.Get("X-ARR-ClientCert")
	if certHeader == "" {
		// No header present — either running locally or cert not forwarded.
		// In production with client_certificate_mode = "Required", Azure will
		// reject requests without a cert before they reach this code.
		// APIM also validates the cert at the gateway layer.
		return nil
	}

	// Decode the base64-encoded certificate
	certBytes, err := base64.StdEncoding.DecodeString(certHeader)
	if err != nil {
		return fmt.Errorf("failed to decode client certificate: %w", err)
	}

	// Parse the certificate
	cert, err := x509.ParseCertificate(certBytes)
	if err != nil {
		return fmt.Errorf("failed to parse client certificate: %w", err)
	}

	// Validate CN matches expected value
	expectedCN := os.Getenv("EXPECTED_CLIENT_CN")
	if expectedCN == "" {
		expectedCN = "api-client.internal.checkout.com"
	}
	if cert.Subject.CommonName != expectedCN {
		return fmt.Errorf("unexpected client CN: got %q, want %q", cert.Subject.CommonName, expectedCN)
	}

	// Validate against CA if CA cert is available
	caCertPEM := os.Getenv("CA_CERT_PEM")
	if caCertPEM != "" {
		pool := x509.NewCertPool()
		block, _ := pem.Decode([]byte(caCertPEM))
		if block == nil {
			return fmt.Errorf("failed to decode CA certificate PEM")
		}
		caCert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return fmt.Errorf("failed to parse CA certificate: %w", err)
		}
		pool.AddCert(caCert)

		opts := x509.VerifyOptions{
			Roots:     pool,
			KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
		}
		if _, err := cert.Verify(opts); err != nil {
			return fmt.Errorf("client certificate verification failed: %w", err)
		}
	}

	return nil
}

func writeError(w http.ResponseWriter, status int, message, requestID string) {
	w.WriteHeader(status)
	resp := ErrorResponse{
		Error:     message,
		RequestID: requestID,
	}
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("[%s] failed to encode error response: %v", requestID, err)
	}
}
