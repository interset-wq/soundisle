package api

import (
	"context"
	"encoding/json"
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
		indexPath:   filepath.Join(dir, "download_index.json"),
		index:       map[string]string{},
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

func TestRepairMissingAssetsQueuesOldDownloads(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	cover := []byte("\xff\xd8\xffbulk-cover")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		_, _ = w.Write(cover)
	}))
	defer server.Close()

	m := newTestDownloadManager(t, dir, store)
	now := time.Now()
	for _, name := range []string{"One", "Two"} {
		audio := filepath.Join(dir, "Artist - "+name+".mp3")
		if err := os.WriteFile(audio, []byte("audio-"+name), 0o644); err != nil {
			t.Fatalf("write audio: %v", err)
		}
		id := "dl-" + strings.ToLower(name)
		m.tasks[id] = &DownloadTask{
			ID: id, Name: name, Source: "netease", Status: "done",
			Path: audio, CreatedAt: now,
			Song: model.Song{
				ID: name, Source: "netease", Name: name, Cover: server.URL + "/cover.jpg",
			},
		}
		m.order = append(m.order, id)
	}
	// Finished but the file is gone: must be skipped, not queued.
	m.tasks["dl-gone"] = &DownloadTask{
		ID: "dl-gone", Name: "Gone", Status: "done",
		Path: filepath.Join(dir, "missing.mp3"), CreatedAt: now,
	}
	m.order = append(m.order, "dl-gone")

	if queued := m.RepairMissingAssets(); queued != 2 {
		t.Fatalf("queued %d tasks, want 2", queued)
	}

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		done := 0
		m.mu.RLock()
		for _, id := range []string{"dl-one", "dl-two"} {
			if task := m.tasks[id]; task != nil && task.CoverPath != "" {
				if _, err := os.Stat(task.CoverPath); err == nil {
					done++
				}
			}
		}
		m.mu.RUnlock()
		if done == 2 {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("bulk repair did not fetch both covers in time")
}

func TestEnqueueSkipsSongsAlreadyQueuedOrOnDisk(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	audio := filepath.Join(dir, "Artist - One.mp3")
	if err := os.WriteFile(audio, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	m.tasks["dl-one"] = &DownloadTask{
		ID: "dl-one", Status: "done", Path: audio,
		Song: model.Song{ID: "1", Source: "netease", Name: "One"},
	}
	m.tasks["dl-two"] = &DownloadTask{
		ID: "dl-two", Status: "downloading",
		Song: model.Song{ID: "2", Source: "netease", Name: "Two"},
	}
	m.tasks["dl-gone"] = &DownloadTask{
		ID: "dl-gone", Status: "done", Path: filepath.Join(dir, "gone.mp3"),
		Song: model.Song{ID: "3", Source: "netease", Name: "Gone"},
	}
	m.order = []string{"dl-one", "dl-two", "dl-gone"}

	queued := m.Enqueue([]model.Song{
		{ID: "1", Source: "netease", Name: "One"},
		{ID: "2", Source: "netease", Name: "Two"},
		{ID: "3", Source: "netease", Name: "Gone"},
		{ID: "1", Source: "netease", Name: "One"},
		{ID: "4", Source: "qq", Name: "Other platform"},
	})
	if len(queued) != 2 {
		t.Fatalf("queued %d tasks, want 2: %+v", len(queued), queued)
	}
	if queued[0].Song.ID != "3" || queued[1].Song.ID != "4" {
		t.Fatalf("unexpected queued songs: %q, %q", queued[0].Song.ID, queued[1].Song.ID)
	}
	if len(m.order) != 5 {
		t.Fatalf("order has %d entries, want 5", len(m.order))
	}
}

func TestDownloadIndexSurvivesClearedHistory(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	audio := filepath.Join(dir, "Artist - Kept.mp3")
	if err := os.WriteFile(audio, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	song := model.Song{ID: "42", Source: "netease", Name: "Kept", Artist: "Artist"}
	m.index[songIdentity(song)] = audio
	m.saveIndex()

	// The user clears the finished list; the file stays on disk.
	reloaded := newTestDownloadManager(t, dir, store)
	reloaded.loadIndex()
	if queued := reloaded.Enqueue([]model.Song{song}); len(queued) != 0 {
		t.Fatalf("queued %d tasks for an already downloaded song", len(queued))
	}
	if keys := reloaded.DownloadedKeys(); len(keys) != 1 || keys[0] != songIdentity(song) {
		t.Fatalf("downloaded keys = %v, want the kept song", keys)
	}

	// Deleting the file outside the app makes the song downloadable again.
	if err := os.Remove(audio); err != nil {
		t.Fatalf("remove audio: %v", err)
	}
	if keys := reloaded.DownloadedKeys(); len(keys) != 0 {
		t.Fatalf("downloaded keys = %v, want none after deleting the file", keys)
	}
	if queued := reloaded.Enqueue([]model.Song{song}); len(queued) != 1 {
		t.Fatalf("queued %d tasks, want 1 after the file was deleted", len(queued))
	}
}

func TestDownloadIndexBackfillsFromFinishedTasks(t *testing.T) {
	dir := t.TempDir()
	store, err := OpenStore(dir)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	m := newTestDownloadManager(t, dir, store)
	audio := filepath.Join(dir, "Old.mp3")
	if err := os.WriteFile(audio, []byte("audio"), 0o644); err != nil {
		t.Fatalf("write audio: %v", err)
	}
	song := model.Song{ID: "7", Source: "qq", Name: "Old"}
	m.tasks["dl-old"] = &DownloadTask{
		ID: "dl-old", Status: "done", Path: audio, Song: song,
	}
	m.loadIndex()
	if keys := m.DownloadedKeys(); len(keys) != 1 || keys[0] != songIdentity(song) {
		t.Fatalf("downloaded keys = %v, want the finished task", keys)
	}
	if raw, err := os.ReadFile(m.indexPath); err != nil {
		t.Fatalf("read index: %v", err)
	} else {
		var stored map[string]string
		if json.Unmarshal(raw, &stored) != nil || stored[songIdentity(song)] != audio {
			t.Fatalf("index was not persisted: %s", raw)
		}
	}
}
