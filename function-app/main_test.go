package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandleMessage_Success(t *testing.T) {
	body := `{"message":"hello world"}`
	req := httptest.NewRequest(http.MethodPost, "/api/message", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleMessage(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp MessageResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Message != "hello world" {
		t.Errorf("expected message 'hello world', got %q", resp.Message)
	}
	if resp.RequestID == "" {
		t.Error("expected non-empty request_id")
	}
	if resp.Timestamp == "" {
		t.Error("expected non-empty timestamp")
	}
	if w.Header().Get("X-Request-ID") == "" {
		t.Error("expected X-Request-ID header")
	}
}

func TestHandleMessage_MethodNotAllowed(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/message", nil)
	w := httptest.NewRecorder()

	handleMessage(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestHandleMessage_InvalidContentType(t *testing.T) {
	body := `{"message":"test"}`
	req := httptest.NewRequest(http.MethodPost, "/api/message", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "text/plain")
	w := httptest.NewRecorder()

	handleMessage(w, req)

	if w.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("expected 415, got %d", w.Code)
	}
}

func TestHandleMessage_InvalidJSON(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api/message", bytes.NewBufferString("not json"))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleMessage(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestHandleMessage_MissingMessage(t *testing.T) {
	body := `{"message":""}`
	req := httptest.NewRequest(http.MethodPost, "/api/message", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleMessage(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestHandleMessage_UnknownFields(t *testing.T) {
	body := `{"message":"test","extra":"field"}`
	req := httptest.NewRequest(http.MethodPost, "/api/message", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleMessage(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for unknown fields, got %d", w.Code)
	}
}

func TestHandleMessage_MessageTooLong(t *testing.T) {
	longMsg := make([]byte, maxMessageLen+1)
	for i := range longMsg {
		longMsg[i] = 'a'
	}
	body, _ := json.Marshal(MessageRequest{Message: string(longMsg)})
	req := httptest.NewRequest(http.MethodPost, "/api/message", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleMessage(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}
