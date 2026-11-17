package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
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
	LyricPath string     `json:"lyricPath,omitempty"`
	CoverPath string     `json:"coverPath,omitempty"`
	Total     int64      `json:"total"`
	Received  int64      `json:"received"`
	CreatedAt time.Time  `json:"createdAt"`
	UpdatedAt time.Time  `json:"updatedAt"`
	Finished  *time.Time `json:"finishedAt,omitempty"`
	// Partial points at the in-progress ".part" file so a retry can resume
	// instead of downloading the whole track again.
	Partial string `json:"partial,omitempty"`
	// Song is kept so history survives restarts and a failed task can be
	// retried without re-searching for the track.
	Song      model.Song `json:"song"`
	canceled  bool
	Repairing bool `json:"repairing,omitempty"`
}

type DownloadManager struct {
	mu        sync.RWMutex
	tasks     map[string]*DownloadTask
	order     []string
	queue     chan string
	store     *Store
	streams   *StreamManager
	withLyric bool

	// Downloads used to live only in memory, so killing the app wiped the
	// history. Records are now mirrored to downloads.json and reloaded on
	// startup; interrupted tasks are surfaced as failed with a clear reason.
	persistPath string
	dirty       bool

	// Repairing old downloads can trigger several platform searches per track.
	// A small gate keeps a "repair everything" tap from flooding the network.
	repairOnce sync.Once
	repairSem  chan struct{}
}

const downloadHistoryLimit = 300

func NewDownloadManager(store *Store, streams *StreamManager) *DownloadManager {
	m := &DownloadManager{
		tasks:     map[string]*DownloadTask{},
		queue:     make(chan string, 1024),
		store:     store,
		streams:   streams,
		withLyric: true,
	}
	if store != nil && store.path != "" {
		m.persistPath = filepath.Join(filepath.Dir(store.path), "downloads.json")
	}
	m.load()
	go m.worker()
	go m.saveLoop()
	return m
}

func (m *DownloadManager) load() {
	if m.persistPath == "" {
		return
	}
	raw, err := os.ReadFile(m.persistPath)
	if err != nil || len(raw) == 0 {
		return
	}
	var records []DownloadTask
	if err := json.Unmarshal(raw, &records); err != nil {
		return
	}
	sort.SliceStable(records, func(i, j int) bool {
		return records[i].CreatedAt.Before(records[j].CreatedAt)
	})
	now := time.Now()
	loaded := make([]*DownloadTask, 0, len(records))
	for i := range records {
		task := records[i]
		if strings.TrimSpace(task.ID) == "" {
			continue
		}
		switch task.Status {
		case "waiting", "downloading":
			// The worker died with the process; nothing is downloading now.
			finished := now
			task.Status = "failed"
			task.Error = "下载被中断（App 已退出），可重试"
			task.Finished = &finished
		case "canceled":
			continue
		}
		if task.Partial != "" {
			if stat, statErr := os.Stat(task.Partial); statErr == nil && stat.Mode().IsRegular() {
				if task.Received < stat.Size() {
					task.Received = stat.Size()
				}
			} else {
				task.Partial = ""
			}
		}
		// Backfill sidecars for tasks created by older versions: the files are
		// already on disk even though the record has no paths yet.
		if task.Status == "done" && task.Path != "" {
			if task.LyricPath == "" {
				if lrc := lyricSidecarPath(task.Path); fileExists(lrc) {
					task.LyricPath = lrc
				}
			}
			if task.CoverPath == "" {
				if side := findSidecarCover(task.Path); side.path != "" {
					task.CoverPath = side.path
				}
			}
		}
		task.canceled = false
		// A repair goroutine cannot survive a restart; clear the flag so the
		// UI does not show an endless spinner.
		task.Repairing = false
		loaded = append(loaded, &task)
	}
	if len(loaded) > downloadHistoryLimit {
		loaded = loaded[len(loaded)-downloadHistoryLimit:]
	}
	m.mu.Lock()
	for _, task := range loaded {
		m.tasks[task.ID] = task
		m.order = append(m.order, task.ID)
	}
	m.mu.Unlock()
	m.flush()
}

func (m *DownloadManager) saveLoop() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		m.flush()
	}
}

// flush writes the current history to disk at most once per dirty period, so
// per-chunk progress updates stay cheap.
func (m *DownloadManager) flush() {
	m.mu.Lock()
	if !m.dirty || m.persistPath == "" {
		m.mu.Unlock()
		return
	}
	m.dirty = false
	path := m.persistPath
	snapshot := make([]DownloadTask, 0, len(m.order))
	for _, id := range m.order {
		if task, ok := m.tasks[id]; ok {
			snapshot = append(snapshot, *task)
		}
	}
	m.mu.Unlock()

	raw, err := json.Marshal(snapshot)
	if err != nil {
		return
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, path)
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
			CreatedAt: now, UpdatedAt: now, Song: song,
		}
		m.tasks[id] = task
		m.order = append(m.order, id)
		out = append(out, *task)
	}
	if len(m.order) > downloadHistoryLimit {
		drop := len(m.order) - downloadHistoryLimit
		for _, id := range m.order[:drop] {
			delete(m.tasks, id)
		}
		m.order = append([]string(nil), m.order[drop:]...)
	}
	m.dirty = true
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
		m.dirty = true
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
		if task.Partial != "" {
			_ = os.Remove(task.Partial)
		}
		delete(m.tasks, id)
	}
	for i, existing := range m.order {
		if existing == id {
			m.order = append(m.order[:i], m.order[i+1:]...)
			break
		}
	}
	m.dirty = true
}

// Retry re-queues a failed task. Completed tasks are rejected so a stray tap
// cannot download the same song twice.
func (m *DownloadManager) Retry(id string) (DownloadTask, error) {
	m.mu.Lock()
	task, ok := m.tasks[id]
	if !ok {
		m.mu.Unlock()
		return DownloadTask{}, errors.New("下载任务不存在")
	}
	switch task.Status {
	case "failed":
	case "waiting", "downloading":
		m.mu.Unlock()
		return DownloadTask{}, errors.New("任务正在进行中")
	default:
		m.mu.Unlock()
		return DownloadTask{}, errors.New("已完成的任务无需重试")
	}
	task.Status = "waiting"
	task.Error = ""
	task.Total = 0
	task.Received = 0
	task.Finished = nil
	task.LyricPath = ""
	task.CoverPath = ""
	task.canceled = false
	task.UpdatedAt = time.Now()
	snapshot := *task
	m.dirty = true
	m.mu.Unlock()

	m.queue <- id
	return snapshot, nil
}

// RepairAssets re-fetches missing lyrics/cover for an already downloaded file.
// This is what lets songs downloaded before 1.0.3 gain their artwork and lyrics
// without re-downloading the audio.
func (m *DownloadManager) RepairAssets(id string) (DownloadTask, error) {
	m.mu.Lock()
	task, ok := m.tasks[id]
	if !ok {
		m.mu.Unlock()
		return DownloadTask{}, errors.New("下载任务不存在")
	}
	if task.Status != "done" {
		m.mu.Unlock()
		return DownloadTask{}, errors.New("只有已完成的下载才能补全资源")
	}
	if task.Path == "" || !fileExists(task.Path) {
		m.mu.Unlock()
		return DownloadTask{}, errors.New("下载文件不存在，请重新下载")
	}
	if task.Repairing {
		m.mu.Unlock()
		return DownloadTask{}, errors.New("正在补全，请稍候")
	}
	task.Repairing = true
	target := task.Path
	song := task.Song
	snapshot := *task
	m.mu.Unlock()

	go func() {
		slot := m.repairSlot()
		slot <- struct{}{}
		defer func() {
			<-slot
			m.mu.Lock()
			if current, ok := m.tasks[id]; ok {
				current.Repairing = false
			}
			m.mu.Unlock()
		}()
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		lyricPath := ""
		if existing := lyricSidecarPath(target); fileExists(existing) {
			lyricPath = existing
		}
		coverPath := ""
		if side := findSidecarCover(target); side.path != "" {
			coverPath = side.path
		}

		var jobs sync.WaitGroup
		if lyricPath == "" {
			jobs.Add(1)
			go func() {
				defer jobs.Done()
				lyricPath = m.saveLyric(target, song)
			}()
		}
		if coverPath == "" {
			jobs.Add(1)
			go func() {
				defer jobs.Done()
				coverPath = m.saveCover(ctx, target, song)
			}()
		}
		jobs.Wait()

		m.Update(id, func(t *DownloadTask) {
			if lyricPath != "" {
				t.LyricPath = lyricPath
			}
			if coverPath != "" {
				t.CoverPath = coverPath
			}
		})
	}()
	return snapshot, nil
}

// repairSlot lazily creates the semaphore so test managers that are built by
// hand get one too.
func (m *DownloadManager) repairSlot() chan struct{} {
	m.repairOnce.Do(func() { m.repairSem = make(chan struct{}, 2) })
	return m.repairSem
}

// RepairMissingAssets queues asset repair for every finished download that is
// still missing lyrics or cover art. Tasks without a local file are skipped;
// they need a real re-download rather than a metadata fix.
func (m *DownloadManager) RepairMissingAssets() int {
	m.mu.RLock()
	ids := make([]string, 0, len(m.order))
	for _, id := range m.order {
		task, ok := m.tasks[id]
		if !ok || task.Status != "done" || task.Path == "" || task.Repairing {
			continue
		}
		if task.LyricPath == "" || task.CoverPath == "" {
			ids = append(ids, id)
		}
	}
	m.mu.RUnlock()

	queued := 0
	for _, id := range ids {
		if _, err := m.RepairAssets(id); err == nil {
			queued++
		}
	}
	return queued
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

	entry, _, err := m.streams.Resolve(ctx, task.Song)
	if err != nil {
		m.fail(id, err)
		return
	}
	ext := strings.TrimSpace(entry.Ext)
	if ext == "" {
		ext = "mp3"
	}
	filename := buildFilename(settings.FilenameTemplate, task.Song, ext)
	outDir := settings.DownloadDir
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		m.fail(id, err)
		return
	}
	target := uniquePath(filepath.Join(outDir, filename))
	// Download into a .part file first: a killed process then leaves no
	// truncated file that the local library would happily list as a song, and
	// a retry can append to it with an HTTP Range request.
	staging := target + ".part"
	m.Update(id, func(t *DownloadTask) { t.Partial = staging })

	isCanceled := func() bool {
		current, ok := m.get(id)
		return !ok || current.canceled
	}

	var written int64
	if entry.FilePath != "" {
		// Copying a local library file cannot be resumed; start clean.
		_ = os.Remove(staging)
		err = copyFile(entry.FilePath, staging, func(n int64) {
			m.Update(id, func(t *DownloadTask) { t.Received = n })
		}, isCanceled)
		if err == nil {
			if stat, statErr := os.Stat(staging); statErr == nil {
				written = stat.Size()
			}
		}
	} else {
		written, err = fetchToFile(ctx, entry.URL, entry.Headers, staging,
			func(received, total int64) {
				m.Update(id, func(t *DownloadTask) {
					t.Received = received
					if total > 0 {
						t.Total = total
					}
				})
			}, isCanceled)
	}

	if err != nil {
		if errors.Is(err, errDownloadCanceled) {
			_ = os.Remove(staging)
			m.Update(id, func(t *DownloadTask) { t.Partial = "" })
			return
		}
		// Protocol errors will not get better on retry, so drop the partial
		// file. Network/IO failures keep it for the resume path.
		var statusErr httpStatusError
		if errors.As(err, &statusErr) || entry.FilePath != "" {
			_ = os.Remove(staging)
			m.Update(id, func(t *DownloadTask) { t.Partial = "" })
		}
		m.fail(id, err)
		return
	}

	if err := os.Rename(staging, target); err != nil {
		m.fail(id, err)
		return
	}
	m.Update(id, func(t *DownloadTask) { t.Partial = "" })

	// Lyrics and cover art are part of "downloaded", not optional extras: a
	// local song without them looks broken in the player. Both requests are
	// best-effort and run in parallel so a missing cover never blocks audio.
	var lyricPath, coverPath string
	var assets sync.WaitGroup
	assets.Add(2)
	go func() {
		defer assets.Done()
		lyricPath = m.saveLyric(target, task.Song)
	}()
	go func() {
		defer assets.Done()
		coverPath = m.saveCover(ctx, target, task.Song)
	}()
	assets.Wait()

	now := time.Now()
	m.Update(id, func(t *DownloadTask) {
		t.Status = "done"
		t.Path = target
		t.LyricPath = lyricPath
		t.CoverPath = coverPath
		t.Total = written
		t.Received = written
		t.Finished = &now
	})
}

// saveLyric writes a `.lrc` sidecar next to the downloaded track. It tries the
// song's own platform first, then searches other platforms for the same title
// and artist, because many providers only expose lyrics on some catalogues.
func (m *DownloadManager) saveLyric(target string, song model.Song) string {
	if !m.withLyric {
		return ""
	}
	lrc := m.findLyric(song)
	if strings.TrimSpace(lrc) == "" {
		return ""
	}
	path := lyricSidecarPath(target)
	if err := writeFileAtomic(path, []byte(lrc)); err != nil {
		return ""
	}
	return path
}

func (m *DownloadManager) findLyric(song model.Song) string {
	if p, err := m.streams.provider(song.Source); err == nil && p.lyric != nil {
		if lrc, err := p.lyric(&song); err == nil && strings.TrimSpace(lrc) != "" {
			return lrc
		}
	}
	// Cross-source fallback: reuse the search used for playback, but only read
	// lyrics and never resolve/download the other platform's audio.
	candidates := m.streams.searchSimilar(song)
	for i, candidate := range candidates {
		if i >= 6 {
			break
		}
		if candidate.Source == song.Source && candidate.ID == song.ID {
			continue
		}
		p, err := m.streams.provider(candidate.Source)
		if err != nil || p.lyric == nil {
			continue
		}
		if lrc, err := p.lyric(&candidate); err == nil && strings.TrimSpace(lrc) != "" {
			return lrc
		}
	}
	return ""
}

const maxCoverBytes = 12 << 20

// saveCover downloads the platform's cover art and stores it next to the audio
// file. Without this, local playback only had artwork when the audio file
// happened to carry an embedded picture.
func (m *DownloadManager) saveCover(ctx context.Context, target string, song model.Song) string {
	raw := strings.TrimSpace(song.Cover)
	if raw == "" {
		return ""
	}
	if strings.HasPrefix(raw, "//") {
		raw = "https:" + raw
	}
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return ""
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if err != nil {
		return ""
	}
	for key, values := range sourceHeaders(song.Source) {
		for _, value := range values {
			req.Header.Add(key, value)
		}
	}
	if cookie := m.store.Cookie(song.Source); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return ""
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxCoverBytes+1))
	if err != nil || len(data) == 0 || len(data) > maxCoverBytes {
		return ""
	}
	mime := strings.TrimSpace(strings.Split(resp.Header.Get("Content-Type"), ";")[0])
	if mime == "" || mime == "application/octet-stream" {
		mime = http.DetectContentType(data)
	}
	if !strings.HasPrefix(mime, "image/") {
		return ""
	}
	ext := ".jpg"
	switch mime {
	case "image/png":
		ext = ".png"
	case "image/webp":
		ext = ".webp"
	case "image/gif":
		ext = ".gif"
	case "image/jpeg", "image/jpg":
		ext = ".jpg"
	}
	base := strings.TrimSuffix(target, filepath.Ext(target))
	for _, old := range sidecarCoverExts {
		_ = os.Remove(base + ".cover" + old)
	}
	path := base + ".cover" + ext
	if err := writeFileAtomic(path, data); err != nil {
		return ""
	}
	return path
}

func writeFileAtomic(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func (m *DownloadManager) fail(id string, err error) {
	now := time.Now()
	m.Update(id, func(t *DownloadTask) {
		t.Status = "failed"
		t.Error = err.Error()
		t.Finished = &now
	})
}

// errDownloadCanceled signals that the user removed the task while bytes were
// still arriving; the caller deletes the part file.
var errDownloadCanceled = errors.New("下载已取消")

// httpStatusError marks a definitive server-side rejection, which is not worth
// resuming.
type httpStatusError struct{ code int }

func (e httpStatusError) Error() string { return fmt.Sprintf("音频服务器返回 HTTP %d", e.code) }

// fetchToFile streams rawURL into path and resumes from the current file size
// when the server answers a Range request with 206. Servers that ignore Range
// simply restart the file from zero.
func fetchToFile(ctx context.Context, rawURL string, headers http.Header, path string,
	onProgress func(received, total int64), canceled func() bool) (int64, error) {
	var offset int64
	if stat, err := os.Stat(path); err == nil && stat.Mode().IsRegular() {
		offset = stat.Size()
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return offset, err
	}
	for key, values := range headers {
		for _, value := range values {
			req.Header.Add(key, value)
		}
	}
	if offset > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", offset))
	}

	resp, err := (&http.Client{}).Do(req)
	if err != nil {
		return offset, err
	}
	defer resp.Body.Close()

	total := resp.ContentLength
	switch resp.StatusCode {
	case http.StatusPartialContent:
		if resp.ContentLength >= 0 {
			total = offset + resp.ContentLength
		}
	case http.StatusOK:
		// Range ignored: rewrite from the beginning.
		offset = 0
	default:
		return offset, httpStatusError{code: resp.StatusCode}
	}

	flags := os.O_CREATE | os.O_WRONLY | os.O_TRUNC
	if offset > 0 {
		flags = os.O_CREATE | os.O_WRONLY | os.O_APPEND
	}
	file, err := os.OpenFile(path, flags, 0o644)
	if err != nil {
		return offset, err
	}

	written := offset
	if onProgress != nil {
		onProgress(written, total)
	}
	buf := make([]byte, 64<<10)
	for {
		if canceled != nil && canceled() {
			file.Close()
			return written, errDownloadCanceled
		}
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if _, writeErr := file.Write(buf[:n]); writeErr != nil {
				file.Close()
				return written, writeErr
			}
			written += int64(n)
			if onProgress != nil {
				onProgress(written, total)
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			file.Close()
			return written, readErr
		}
	}
	if err := file.Close(); err != nil {
		return written, err
	}
	if total > 0 && written < total {
		return written, fmt.Errorf("下载不完整：%d/%d 字节", written, total)
	}
	return written, nil
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
