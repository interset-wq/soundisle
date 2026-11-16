package api

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newTestLibrary(t *testing.T) (*Library, string) {
	t.Helper()
	dataDir := t.TempDir()
	store, err := OpenStore(dataDir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	settings := store.Settings()
	settings.DownloadDir = filepath.Join(dataDir, "downloads")
	if _, err := store.UpdateSettings(settings); err != nil {
		t.Fatalf("update settings: %v", err)
	}
	return NewLibrary(dataDir, store), settings.DownloadDir
}

func TestDeleteManyRemovesFilesAndLyrics(t *testing.T) {
	lib, dir := newTestLibrary(t)
	first := filepath.Join(dir, "Artist - One.mp3")
	second := filepath.Join(dir, "Artist - Two.mp3")
	for _, path := range []string{first, second} {
		if err := os.WriteFile(path, []byte("audio"), 0o644); err != nil {
			t.Fatalf("write %s: %v", path, err)
		}
	}
	lrc := strings.TrimSuffix(first, filepath.Ext(first)) + ".lrc"
	if err := os.WriteFile(lrc, []byte("[00:00.00]hi"), 0o644); err != nil {
		t.Fatalf("write lrc: %v", err)
	}
	if _, err := lib.Scan(); err != nil {
		t.Fatalf("scan: %v", err)
	}
	if got := lib.Count(); got != 2 {
		t.Fatalf("scanned %d files, want 2", got)
	}

	outside := filepath.Join(t.TempDir(), "outside.mp3")
	if err := os.WriteFile(outside, []byte("keep"), 0o644); err != nil {
		t.Fatalf("write outside: %v", err)
	}
	deleted, failed := lib.DeleteMany([]string{first, outside, filepath.Join(dir, "missing.mp3")})
	if deleted != 1 {
		t.Fatalf("deleted %d, want 1", deleted)
	}
	if len(failed) != 2 {
		t.Fatalf("failed = %v, want 2 entries", failed)
	}
	if _, err := os.Stat(first); !os.IsNotExist(err) {
		t.Fatalf("deleted file still exists: %v", err)
	}
	if _, err := os.Stat(lrc); !os.IsNotExist(err) {
		t.Fatalf("sidecar lyrics were not removed: %v", err)
	}
	if _, err := os.Stat(outside); err != nil {
		t.Fatalf("file outside the download dir was touched: %v", err)
	}
	if _, err := os.Stat(second); err != nil {
		t.Fatalf("unselected file was removed: %v", err)
	}
	if got := lib.Count(); got != 1 {
		t.Fatalf("library has %d entries, want 1", got)
	}
}

func TestDeleteManyRejectsOutsidePathsOnly(t *testing.T) {
	lib, dir := newTestLibrary(t)
	inside := filepath.Join(dir, "Inside.mp3")
	if err := os.WriteFile(inside, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
	if _, err := lib.Scan(); err != nil {
		t.Fatalf("scan: %v", err)
	}
	deleted, failed := lib.DeleteMany([]string{filepath.Join(dir, "..", "state.json"), inside})
	if deleted != 1 || len(failed) != 1 {
		t.Fatalf("deleted=%d failed=%v, want 1/1", deleted, failed)
	}
}
