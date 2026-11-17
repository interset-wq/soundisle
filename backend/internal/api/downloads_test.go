package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/guohuiyuan/music-lib/model"
)

// newTestDownloadManager builds a DownloadManager without starting the worker
// goroutines, so persistence can be exercised deterministically.
func newTestDownloadManager(t *testing.T, dir string, store *Store) *DownloadManager {
	t.Helper()
	return &DownloadManager{
		tasks:       map[string]*DownloadTask{},
		queue:       make(chan string, 16),
		store:       store,
		streams:     NewStreamManager(dir, store),
		persistPath: filepath.Join(dir, "downloads.json"),
	}
}

func TestDownloadHistorySurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	now := time.Now()
	m.tasks["dl-done"] = &DownloadTask{
		ID: "dl-done", Name: "Finished", Source: "netease", Status: "done",
		Path: "/music/Finished.mp3", CreatedAt: now.Add(-time.Minute),
		Song: model.Song{ID: "1", Source: "netease", Name: "Finished"},
	}
	m.tasks["dl-busy"] = &DownloadTask{
		ID: "dl-busy", Name: "Interrupted", Source: "netease", Status: "downloading",
		CreatedAt: now,
		Song:      model.Song{ID: "2", Source: "netease", Name: "Interrupted"},
	}
	m.order = []string{"dl-done", "dl-busy"}
	m.dirty = true
	m.flush()

	data, err := os.ReadFile(m.persistPath)
	if err != nil || len(data) == 0 {
		t.Fatalf("downloads.json not written: %v", err)
	}

	reloaded := newTestDownloadManager(t, dir, store)
	reloaded.load()
	tasks := reloaded.List()
	if len(tasks) != 2 {
		t.Fatalf("loaded %d tasks, want 2", len(tasks))
	}
	// List returns newest first, so the interrupted task is on top.
	if tasks[0].ID != "dl-busy" {
		t.Fatalf("newest task = %q, want dl-busy", tasks[0].ID)
	}
	if tasks[0].Status != "failed" {
		t.Fatalf("interrupted status = %q, want failed", tasks[0].Status)
	}
	if !strings.Contains(tasks[0].Error, "中断") {
		t.Fatalf("interrupted error = %q, want a friendly reason", tasks[0].Error)
	}
	if tasks[1].Status != "done" || tasks[1].Path != "/music/Finished.mp3" {
		t.Fatalf("finished task was not restored: %+v", tasks[1])
	}
	if tasks[1].Song.Name != "Finished" {
		t.Fatalf("song metadata was not restored: %+v", tasks[1].Song)
	}
}

func TestRetryRequeuesFailedTask(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	m.tasks["dl-1"] = &DownloadTask{
		ID: "dl-1", Name: "Broken", Source: "netease", Status: "failed",
		Error: "网络错误", CreatedAt: time.Now(), Received: 42, Total: 100,
		Song: model.Song{ID: "1", Source: "netease", Name: "Broken"},
	}
	m.tasks["dl-2"] = &DownloadTask{
		ID: "dl-2", Name: "Fine", Source: "netease", Status: "done",
		CreatedAt: time.Now(),
		Song:      model.Song{ID: "2", Source: "netease", Name: "Fine"},
	}
	m.order = []string{"dl-1", "dl-2"}

	task, err := m.Retry("dl-1")
	if err != nil {
		t.Fatalf("retry failed task: %v", err)
	}
	if task.Status != "waiting" || task.Error != "" || task.Received != 0 {
		t.Fatalf("retry did not reset the task: %+v", task)
	}
	select {
	case id := <-m.queue:
		if id != "dl-1" {
			t.Fatalf("queued %q, want dl-1", id)
		}
	default:
		t.Fatal("retried task was not queued")
	}

	if _, err := m.Retry("dl-2"); err == nil {
		t.Fatal("expected retry of a finished task to fail")
	}
	if _, err := m.Retry("missing"); err == nil {
		t.Fatal("expected retry of an unknown task to fail")
	}
}

func TestRemoveDeletesPartialFile(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	partial := filepath.Join(dir, "track.mp3.part")
	if err := os.WriteFile(partial, []byte("partial"), 0o644); err != nil {
		t.Fatalf("write part file: %v", err)
	}
	m.tasks["dl-1"] = &DownloadTask{
		ID: "dl-1", Name: "Broken", Source: "netease", Status: "failed",
		Partial: partial, CreatedAt: time.Now(),
	}
	m.order = []string{"dl-1"}

	m.Remove("dl-1")
	if _, err := os.Stat(partial); !os.IsNotExist(err) {
		t.Fatalf("partial file still exists after remove: %v", err)
	}
}

func TestSaveCoverWritesSidecar(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	cover := []byte("\x89PNG\r\n\x1a\ncover-bytes")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		_, _ = w.Write(cover)
	}))
	defer server.Close()

	m := newTestDownloadManager(t, dir, store)
	target := filepath.Join(dir, "Artist - Song.mp3")
	path := m.saveCover(context.Background(), target, model.Song{
		ID: "1", Source: "netease", Name: "Song", Cover: server.URL + "/cover.png",
	})
	want := filepath.Join(dir, "Artist - Song.cover.png")
	if path != want {
		t.Fatalf("cover path = %q, want %q", path, want)
	}
	got, err := os.ReadFile(path)
	if err != nil || string(got) != string(cover) {
		t.Fatalf("cover content = %q, %v", got, err)
	}
}

func TestSaveCoverIgnoresNonImage(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		_, _ = w.Write([]byte("<html>not an image</html>"))
	}))
	defer server.Close()

	m := newTestDownloadManager(t, dir, store)
	target := filepath.Join(dir, "Artist - Song.mp3")
	if path := m.saveCover(context.Background(), target, model.Song{
		ID: "1", Source: "netease", Name: "Song", Cover: server.URL + "/cover.jpg",
	}); path != "" {
		t.Fatalf("non-image cover was saved at %q", path)
	}
}

func TestLoadBackfillsSidecarsForDoneTasks(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	audio := filepath.Join(dir, "Artist - Song.mp3")
	if err := os.WriteFile(audio, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	base := strings.TrimSuffix(audio, filepath.Ext(audio))
	if err := os.WriteFile(base+".lrc", []byte("[00:00.00]hi"), 0o644); err != nil {
		t.Fatalf("write lrc: %v", err)
	}
	if err := os.WriteFile(base+".cover.jpg", []byte("cover"), 0o644); err != nil {
		t.Fatalf("write cover: %v", err)
	}

	m := newTestDownloadManager(t, dir, store)
	m.tasks["dl-1"] = &DownloadTask{
		ID: "dl-1", Name: "Song", Source: "netease", Status: "done",
		Path: audio, CreatedAt: time.Now(),
		Song: model.Song{ID: "1", Source: "netease", Name: "Song"},
	}
	m.order = []string{"dl-1"}
	m.dirty = true
	m.flush()

	reloaded := newTestDownloadManager(t, dir, store)
	reloaded.load()
	tasks := reloaded.List()
	if len(tasks) != 1 {
		t.Fatalf("loaded %d tasks, want 1", len(tasks))
	}
	if tasks[0].LyricPath != base+".lrc" {
		t.Fatalf("lyric path = %q", tasks[0].LyricPath)
	}
	if tasks[0].CoverPath != base+".cover.jpg" {
		t.Fatalf("cover path = %q", tasks[0].CoverPath)
	}
}

func TestRepairAssetsFetchesMissingCover(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	cover := []byte("\xff\xd8\xffcover")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		_, _ = w.Write(cover)
	}))
	defer server.Close()

	audio := filepath.Join(dir, "Artist - Song.mp3")
	if err := os.WriteFile(audio, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	m.tasks["dl-1"] = &DownloadTask{
		ID: "dl-1", Name: "Song", Source: "netease", Status: "done",
		Path: audio, CreatedAt: time.Now(),
		Song: model.Song{
			ID: "1", Source: "netease", Name: "Song", Cover: server.URL + "/cover.jpg",
		},
	}
	m.order = []string{"dl-1"}

	if _, err := m.RepairAssets("dl-1"); err != nil {
		t.Fatalf("repair: %v", err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if task, ok := m.get("dl-1"); ok && task.CoverPath != "" {
			if got, err := os.ReadFile(task.CoverPath); err != nil || string(got) != string(cover) {
				t.Fatalf("cover = %q, %v", got, err)
			}
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("cover was not repaired in time")
}

func TestRepairAssetsRejectsUnfinishedTask(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	m.tasks["dl-1"] = &DownloadTask{
		ID: "dl-1", Name: "Song", Status: "downloading", CreatedAt: time.Now(),
	}
	if _, err := m.RepairAssets("dl-1"); err == nil {
		t.Fatal("expected unfinished task to be rejected")
	}
}
