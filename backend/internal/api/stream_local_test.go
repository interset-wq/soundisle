package api

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/guohuiyuan/music-lib/model"
)

func TestResolveLocalFileServesAndKeepsIt(t *testing.T) {
	dataDir := t.TempDir()
	store, err := OpenStore(dataDir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	path := filepath.Join(store.Settings().DownloadDir, "Artist - Song.mp3")
	if err := os.WriteFile(path, []byte("ID3fake"), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	manager := NewStreamManager(dataDir, store)
	song := model.Song{
		ID:     "local:" + path,
		Source: "local",
		Name:   "Song",
		Artist: "Artist",
		Link:   path,
		Ext:    "mp3",
	}
	entry, token, err := manager.Resolve(context.Background(), song)
	if err != nil {
		t.Fatalf("resolve local: %v", err)
	}
	if entry.FilePath != path {
		t.Fatalf("file path = %q, want %q", entry.FilePath, path)
	}
	if token == "" {
		t.Fatal("empty stream token")
	}
	if entry.ContentType != "audio/mpeg" {
		t.Fatalf("content type = %q, want audio/mpeg", entry.ContentType)
	}

	// Expiring the stream token must not delete the user's downloaded file.
	manager.mu.Lock()
	manager.entries[token].ExpiresAt = time.Now().Add(-time.Minute)
	manager.mu.Unlock()
	manager.Cleanup()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("local file was removed by stream cleanup: %v", err)
	}
}

func TestResolveLocalRejectsPathOutsideDownloadDir(t *testing.T) {
	dataDir := t.TempDir()
	store, err := OpenStore(dataDir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	outside := filepath.Join(t.TempDir(), "secret.mp3")
	if err := os.WriteFile(outside, []byte("ID3fake"), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	manager := NewStreamManager(dataDir, store)
	_, _, err = manager.Resolve(context.Background(), model.Song{
		ID:     "local:" + outside,
		Source: "local",
		Name:   "Secret",
		Link:   outside,
	})
	if err == nil {
		t.Fatal("expected path outside download dir to be rejected")
	}
}

func TestResolveLocalMissingFile(t *testing.T) {
	dataDir := t.TempDir()
	store, err := OpenStore(dataDir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	manager := NewStreamManager(dataDir, store)
	_, _, err = manager.Resolve(context.Background(), model.Song{
		ID:     "local:/nope.mp3",
		Source: "local",
		Name:   "Gone",
		Link:   filepath.Join(store.Settings().DownloadDir, "gone.mp3"),
	})
	if err == nil {
		t.Fatal("expected missing local file to fail")
	}
}
