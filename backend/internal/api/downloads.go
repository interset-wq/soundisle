package api

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/guohuiyuan/music-lib/model"
)

type DownloadTask struct {
	ID        string     `json:"id"`
	Name      string     `json:"name"`
	Artist    string     `json:"artist"`
	Album     string     `json:"album"`
	Cover     string     `json:"cover"`
	Source    string     `json:"source"`
	Status    string     `json:"status"` // waiting | downloading | done | failed | canceled
	Error     string     `json:"error,omitempty"`
	Path      string     `json:"path,omitempty"`
	Total     int64      `json:"total"`
	Received  int64      `json:"received"`
	CreatedAt time.Time  `json:"createdAt"`
	UpdatedAt time.Time  `json:"updatedAt"`
	Finished  *time.Time `json:"finishedAt,omitempty"`
	song      model.Song
	canceled  bool
}

type DownloadManager struct {
	mu       sync.RWMutex
	tasks    map[string]*DownloadTask
	order    []string
	queue    chan string
	store    *Store
	streams  *StreamManager
	withLyric bool
}

func NewDownloadManager(store *Store, streams *StreamManager) *DownloadManager {
	m := &DownloadManager{
		tasks:    map[string]*DownloadTask{},
		queue:    make(chan string, 1024),
		store:    store,
		streams:  streams,
		withLyric: true,
	}
	go m.worker()
	return m
}

func (m *DownloadManager) Enqueue(songs []model.Song) []DownloadTask {
	now := time.Now()
	out := make([]DownloadTask, 0, len(songs))
	m.mu.Lock()
	for _, song := range songs {
		if strings.TrimSpace(song.ID) == "" || strings.TrimSpace(song.Source) == "" {
			continue
		}
		id := newID("dl")
		task := &DownloadTask{
			ID: id, Name: song.Name, Artist: song.Artist, Album: song.Album,
			Cover: song.Cover, Source: song.Source, Status: "waiting",
			CreatedAt: now, UpdatedAt: now, song: song,
		}
		m.tasks[id] = task
		m.order = append(m.order, id)
		out = append(out, *task)
	}
	m.mu.Unlock()
	for _, task := range out {
		m.queue <- task.ID
	}
	return out
}

func (m *DownloadManager) List() []DownloadTask {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]DownloadTask, 0, len(m.order))
	for i := len(m.order) - 1; i >= 0; i-- {
		if task, ok := m.tasks[m.order[i]]; ok {
			out = append(out, *task)
		}
	}
	return out
}

func (m *DownloadManager) Update(id string, fn func(*DownloadTask)) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if task, ok := m.tasks[id]; ok {
		fn(task)
		task.UpdatedAt = time.Now()
	}
}

func (m *DownloadManager) get(id string) (*DownloadTask, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	task, ok := m.tasks[id]
	if !ok {
		return nil, false
	}
	copy := *task
	return &copy, true
}

func (m *DownloadManager) Remove(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if task, ok := m.tasks[id]; ok {
		task.canceled = true
		delete(m.tasks, id)
	}
	for i, existing := range m.order {
		if existing == id {
			m.order = append(m.order[:i], m.order[i+1:]...)
			break
		}
	}
}

func (m *DownloadManager) worker() {
	for id := range m.queue {
		m.process(id)
	}
}

func (m *DownloadManager) process(id string) {
	task, ok := m.get(id)
	if !ok || task.canceled {
		return
	}
	m.Update(id, func(t *DownloadTask) { t.Status = "downloading" })
	defer func() {
		if r := recover(); r != nil {
			m.fail(id, fmt.Errorf("下载异常: %v", r))
		}
	}()

	settings := m.store.Settings()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	entry, _, err := m.streams.Resolve(ctx, task.song)
	if err != nil {
		m.fail(id, err)
		return
	}
	ext := strings.TrimSpace(entry.Ext)
	if ext == "" {
		ext = "mp3"
	}
	filename := buildFilename(settings.FilenameTemplate, task.song, ext)
	outDir := settings.DownloadDir
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		m.fail(id, err)
		return
	}
	target := uniquePath(filepath.Join(outDir, filename))

	var written int64
	if entry.FilePath != "" {
		if err := copyFile(entry.FilePath, target, func(n int64) {
			m.Update(id, func(t *DownloadTask) { t.Received = n })
		}, func() bool {
			current, ok := m.get(id)
			return !ok || current.canceled
		}); err != nil {
			m.fail(id, err)
			return
		}
		stat, _ := os.Stat(target)
		if stat != nil {
			written = stat.Size()
		}
	} else {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, entry.URL, nil)
		if err != nil {
			m.fail(id, err)
			return
		}
		for k, values := range entry.Headers {
			for _, v := range values {
				req.Header.Add(k, v)
			}
		}
		client := &http.Client{Timeout: 0}
		resp, err := client.Do(req)
		if err != nil {
			m.fail(id, err)
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			m.fail(id, fmt.Errorf("音频服务器返回 HTTP %d", resp.StatusCode))
			return
		}
		total := resp.ContentLength
		m.Update(id, func(t *DownloadTask) { t.Total = total })
		f, err := os.Create(target)
		if err != nil {
			m.fail(id, err)
			return
		}
		buf := make([]byte, 64<<10)
		for {
			current, ok := m.get(id)
			if !ok || current.canceled {
				f.Close()
				os.Remove(target)
				return
			}
			n, readErr := resp.Body.Read(buf)
			if n > 0 {
				if _, writeErr := f.Write(buf[:n]); writeErr != nil {
					f.Close()
					m.fail(id, writeErr)
					return
				}
				written += int64(n)
				m.Update(id, func(t *DownloadTask) { t.Received = written })
			}
			if readErr == io.EOF {
				break
			}
			if readErr != nil {
				f.Close()
				os.Remove(target)
				m.fail(id, readErr)
				return
			}
		}
		if err := f.Close(); err != nil {
			m.fail(id, err)
			return
		}
	}

	if m.withLyric {
		if p, err := m.streams.provider(task.song.Source); err == nil && p.lyric != nil {
			if lrc, err := p.lyric(&task.song); err == nil && strings.TrimSpace(lrc) != "" {
				lrcPath := strings.TrimSuffix(target, filepath.Ext(target)) + ".lrc"
				_ = os.WriteFile(lrcPath, []byte(lrc), 0o644)
			}
		}
	}
	now := time.Now()
	m.Update(id, func(t *DownloadTask) {
		t.Status = "done"
		t.Path = target
		t.Total = written
		t.Received = written
		t.Finished = &now
	})
}

func (m *DownloadManager) fail(id string, err error) {
	now := time.Now()
	m.Update(id, func(t *DownloadTask) {
		t.Status = "failed"
		t.Error = err.Error()
		t.Finished = &now
	})
}

func buildFilename(template string, song model.Song, ext string) string {
	if strings.TrimSpace(template) == "" {
		template = "{artist} - {name}"
	}
	name := strings.TrimSpace(song.Name)
	if name == "" {
		name = "Unknown"
	}
	artist := strings.TrimSpace(song.Artist)
	if artist == "" {
		artist = "Unknown"
	}
	replacer := strings.NewReplacer(
		"{name}", sanitizeFilename(name),
		"{artist}", sanitizeFilename(artist),
		"{album}", sanitizeFilename(song.Album),
		"{source}", sanitizeFilename(song.Source),
		"{id}", sanitizeFilename(song.ID),
		"{ext}", ext,
	)
	base := strings.TrimSpace(replacer.Replace(template))
	base = strings.Trim(base, " .-_")
	if base == "" {
		base = sanitizeFilename(artist + " - " + name)
	}
	if !strings.HasSuffix(strings.ToLower(base), "."+strings.ToLower(ext)) {
		base += "." + ext
	}
	if len(base) > 180 {
		base = base[len(base)-180:]
	}
	return base
}

func sanitizeFilename(value string) string {
	value = strings.TrimSpace(value)
	replacer := strings.NewReplacer(
		"/", "／", "\\", "＼", ":", "：", "*", "＊", "?", "？",
		`"`, "＂", "<", "＜", ">", "＞", "|", "｜", "\x00", "",
	)
	value = replacer.Replace(value)
	value = strings.Trim(value, " .")
	if value == "" {
		return "Unknown"
	}
	return value
}

func uniquePath(path string) string {
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		return path
	}
	ext := filepath.Ext(path)
	base := strings.TrimSuffix(path, ext)
	for i := 1; i < 1000; i++ {
		candidate := fmt.Sprintf("%s (%d)%s", base, i, ext)
		if _, err := os.Stat(candidate); errors.Is(err, os.ErrNotExist) {
			return candidate
		}
	}
	return path
}

func copyFile(src, dst string, progress func(int64), canceled func() bool) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	buf := make([]byte, 128<<10)
	var total int64
	for {
		if canceled != nil && canceled() {
			out.Close()
			os.Remove(dst)
			return errors.New("已取消")
		}
		n, readErr := in.Read(buf)
		if n > 0 {
			if _, err := out.Write(buf[:n]); err != nil {
				out.Close()
				return err
			}
			total += int64(n)
			if progress != nil {
				progress(total)
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			out.Close()
			os.Remove(dst)
			return readErr
		}
	}
	return out.Close()
}
