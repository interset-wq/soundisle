package api

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func testAudio(size int) []byte {
	data := make([]byte, size)
	for i := range data {
		data[i] = byte(i % 251)
	}
	return data
}

func TestFetchToFileDownloadsWholeFile(t *testing.T) {
	payload := testAudio(4096)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, "track.mp3", time.Now(), bytes.NewReader(payload))
	}))
	defer server.Close()

	path := filepath.Join(t.TempDir(), "track.mp3.part")
	var lastReceived, lastTotal int64
	size, err := fetchToFile(context.Background(), server.URL, nil, path, func(received, total int64) {
		lastReceived, lastTotal = received, total
	}, nil)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if size != int64(len(payload)) {
		t.Fatalf("size = %d, want %d", size, len(payload))
	}
	if lastReceived != int64(len(payload)) || lastTotal != int64(len(payload)) {
		t.Fatalf("progress = %d/%d, want %d/%d", lastReceived, lastTotal, len(payload), len(payload))
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read part file: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatal("downloaded bytes differ from the payload")
	}
}

func TestFetchToFileResumesWithRange(t *testing.T) {
	payload := testAudio(4096)
	var sawRange string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sawRange = r.Header.Get("Range")
		http.ServeContent(w, r, "track.mp3", time.Now(), bytes.NewReader(payload))
	}))
	defer server.Close()

	path := filepath.Join(t.TempDir(), "track.mp3.part")
	prefix := payload[:1024]
	if err := os.WriteFile(path, prefix, 0o644); err != nil {
		t.Fatalf("seed part file: %v", err)
	}

	var firstReceived int64
	calls := 0
	size, err := fetchToFile(context.Background(), server.URL, nil, path, func(received, total int64) {
		if calls == 0 {
			firstReceived = received
		}
		calls++
	}, nil)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if sawRange != "bytes=1024-" {
		t.Fatalf("Range header = %q, want bytes=1024-", sawRange)
	}
	if firstReceived != 1024 {
		t.Fatalf("first progress = %d, want 1024 (resumed offset)", firstReceived)
	}
	if size != int64(len(payload)) {
		t.Fatalf("size = %d, want %d", size, len(payload))
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read part file: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatal("resumed file is corrupted")
	}
}

func TestFetchToFileRestartsWhenRangeIgnored(t *testing.T) {
	payload := testAudio(2048)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "2048")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(payload)
	}))
	defer server.Close()

	path := filepath.Join(t.TempDir(), "track.mp3.part")
	if err := os.WriteFile(path, testAudio(512), 0o644); err != nil {
		t.Fatalf("seed part file: %v", err)
	}

	size, err := fetchToFile(context.Background(), server.URL, nil, path, nil, nil)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if size != int64(len(payload)) {
		t.Fatalf("size = %d, want %d", size, len(payload))
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read part file: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatal("file was not rewritten from the start")
	}
}

func TestFetchToFileStatusError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "gone", http.StatusGone)
	}))
	defer server.Close()

	path := filepath.Join(t.TempDir(), "track.mp3.part")
	_, err := fetchToFile(context.Background(), server.URL, nil, path, nil, nil)
	if err == nil {
		t.Fatal("expected an error for HTTP 410")
	}
	var statusErr httpStatusError
	if !errors.As(err, &statusErr) || statusErr.code != http.StatusGone {
		t.Fatalf("error = %v, want httpStatusError(410)", err)
	}
}

func TestFetchToFileHonoursCancel(t *testing.T) {
	payload := testAudio(8192)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "8192")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(payload)
	}))
	defer server.Close()

	path := filepath.Join(t.TempDir(), "track.mp3.part")
	_, err := fetchToFile(context.Background(), server.URL, nil, path, nil, func() bool { return true })
	if !errors.Is(err, errDownloadCanceled) {
		t.Fatalf("error = %v, want errDownloadCanceled", err)
	}
}
