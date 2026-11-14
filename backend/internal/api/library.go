package api

import (
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

	"github.com/dhowden/tag"
	"github.com/guohuiyuan/music-lib/model"
)

var audioExtensions = map[string]bool{
	".mp3": true, ".flac": true, ".m4a": true, ".aac": true,
	".ogg": true, ".opus": true, ".wav": true, ".wma": true,
}

type localEntry struct {
	song    model.Song
	path    string
	modTime time.Time
	size    int64
	cover   []byte
	coverMime string
}

type Library struct {
	mu      sync.RWMutex
	store   *Store
	entries map[string]*localEntry
	dataDir string
}

func NewLibrary(dataDir string, store *Store) *Library {
	return &Library{store: store, entries: map[string]*localEntry{}, dataDir: dataDir}
}

func (l *Library) Scan() ([]model.Song, error) {
	settings := l.store.Settings()
	root := settings.DownloadDir
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	next := map[string]*localEntry{}
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d == nil || d.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if !audioExtensions[ext] {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		entry := l.entryFor(path, info)
		next[path] = entry
		return nil
	})
	if err != nil {
		return nil, err
	}
	l.mu.Lock()
	l.entries = next
	l.mu.Unlock()
	return l.Songs("", 0, 0), nil
}

func (l *Library) entryFor(path string, info os.FileInfo) *localEntry {
	l.mu.RLock()
	existing := l.entries[path]
	l.mu.RUnlock()
	if existing != nil && existing.modTime.Equal(info.ModTime()) && existing.size == info.Size() {
		return existing
	}
	entry := &localEntry{path: path, modTime: info.ModTime(), size: info.Size()}
	song := model.Song{
		ID:     "local:" + path,
		Source: "local",
		Ext:    strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), "."),
		Size:   info.Size(),
		Link:   path,
		URL:    "/api/library/stream?path=" + url.QueryEscape(path),
		Cover:  "/api/library/cover?path=" + url.QueryEscape(path),
		Extra:  map[string]string{"path": path, "fileName": filepath.Base(path)},
	}
	base := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	if parts := strings.SplitN(base, " - ", 2); len(parts) == 2 {
		song.Artist = strings.TrimSpace(parts[0])
		song.Name = strings.TrimSpace(parts[1])
	} else {
		song.Name = base
		song.Artist = "未知歌手"
	}
	if f, err := os.Open(path); err == nil {
		defer f.Close()
		if meta, err := tag.ReadFrom(f); err == nil {
			if v := strings.TrimSpace(meta.Title()); v != "" {
				song.Name = v
			}
			if v := strings.TrimSpace(meta.Artist()); v != "" {
				song.Artist = v
			}
			if v := strings.TrimSpace(meta.Album()); v != "" {
				song.Album = v
			}
			if pic := meta.Picture(); pic != nil {
				entry.cover = pic.Data
				entry.coverMime = pic.MIMEType
			}
		}
	}
	entry.song = song
	return entry
}

func (l *Library) Songs(query string, offset, limit int) []model.Song {
	l.mu.RLock()
	defer l.mu.RUnlock()
	query = strings.ToLower(strings.TrimSpace(query))
	all := make([]model.Song, 0, len(l.entries))
	for _, e := range l.entries {
		if query != "" {
			haystack := strings.ToLower(e.song.Name + " " + e.song.Artist + " " + e.song.Album)
			if !strings.Contains(haystack, query) {
				continue
			}
		}
		all = append(all, e.song)
	}
	sort.SliceStable(all, func(i, j int) bool {
		if all[i].Artist == all[j].Artist {
			return all[i].Name < all[j].Name
		}
		return all[i].Artist < all[j].Artist
	})
	if offset < 0 {
		offset = 0
	}
	if limit > 0 {
		if offset >= len(all) {
			return []model.Song{}
		}
		end := offset + limit
		if end > len(all) {
			end = len(all)
		}
		return all[offset:end]
	}
	if offset > 0 {
		if offset >= len(all) {
			return []model.Song{}
		}
		return all[offset:]
	}
	return all
}

func (l *Library) Count() int {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return len(l.entries)
}

func (l *Library) ServeFile(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "path is required", http.StatusBadRequest)
		return
	}
	if !l.within(path) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	f, err := os.Open(path)
	if err != nil {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil || stat.IsDir() {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", mimeForExt(filepath.Ext(path)))
	w.Header().Set("Accept-Ranges", "bytes")
	http.ServeContent(w, r, filepath.Base(path), stat.ModTime(), f)
}

func (l *Library) ServeCover(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" || !l.within(path) {
		http.NotFound(w, r)
		return
	}
	l.mu.RLock()
	entry := l.entries[path]
	l.mu.RUnlock()
	if entry == nil {
		info, err := os.Stat(path)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		entry = l.entryFor(path, info)
	}
	if len(entry.cover) == 0 {
		http.NotFound(w, r)
		return
	}
	mime := entry.coverMime
	if mime == "" {
		mime = "image/jpeg"
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Cache-Control", "public, max-age=86400")
	_, _ = w.Write(entry.cover)
}

func (l *Library) within(path string) bool {
	clean := filepath.Clean(path)
	root := filepath.Clean(l.store.Settings().DownloadDir)
	rel, err := filepath.Rel(root, clean)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func (l *Library) Delete(path string) error {
	if !l.within(path) {
		return errors.New("只能删除下载目录内的文件")
	}
	if err := os.Remove(path); err != nil {
		return err
	}
	_ = os.Remove(strings.TrimSuffix(path, filepath.Ext(path)) + ".lrc")
	l.mu.Lock()
	delete(l.entries, path)
	l.mu.Unlock()
	return nil
}

func (l *Library) Export(path string) (*os.File, os.FileInfo, error) {
	if !l.within(path) {
		return nil, nil, errors.New("forbidden")
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, err
	}
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, nil, err
	}
	return f, info, nil
}

func (l *Library) Debug() string {
	return fmt.Sprintf("library: %d files", l.Count())
}

var _ = io.EOF
