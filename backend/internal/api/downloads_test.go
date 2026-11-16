package api

import (
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
