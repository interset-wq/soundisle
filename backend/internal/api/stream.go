package api

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/guohuiyuan/music-lib/migu"
	"github.com/guohuiyuan/music-lib/model"
	"github.com/guohuiyuan/music-lib/soda"
)

const (
	commonUA    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
	mobileUA    = "Mozilla/5.0 (iPhone; CPU iPhone OS 9_1 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13B143 Safari/601.1"
	streamTTL   = 6 * time.Hour
	streamLimit = 512
)

type streamEntry struct {
	Song        model.Song
	URL         string
	Headers     http.Header
	FilePath    string
	Ext         string
	ContentType string
	Preview     bool
	ExpiresAt   time.Time
}

type StreamManager struct {
	mu      sync.Mutex
	entries map[string]*streamEntry
	dataDir string
	store   *Store
}

func NewStreamManager(dataDir string, store *Store) *StreamManager {
	return &StreamManager{entries: map[string]*streamEntry{}, dataDir: dataDir, store: store}
}

func token() string {
	buf := make([]byte, 24)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}

func sourceHeaders(source string) http.Header {
	h := make(http.Header)
	h.Set("User-Agent", commonUA)
	switch source {
	case "bilibili":
		h.Set("Referer", "https://www.bilibili.com/")
	case "netease":
		h.Set("Referer", "http://music.163.com/")
	case "migu":
		h.Set("User-Agent", mobileUA)
		h.Set("Referer", "http://music.migu.cn/")
	case "qq":
		h.Set("Referer", "http://y.qq.com")
	case "kugou":
		h.Set("Referer", "https://www.kugou.com/")
	case "kuwo":
		h.Set("Referer", "https://www.kuwo.cn/")
	case "soda":
		h.Set("Referer", "https://music.douyin.com/")
	}
	return h
}

func (m *StreamManager) add(entry *streamEntry) string {
	t := token()
	entry.ExpiresAt = time.Now().Add(streamTTL)
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.entries) >= streamLimit {
		now := time.Now()
		for key, e := range m.entries {
			if now.After(e.ExpiresAt) {
				removeEntryFile(e)
				delete(m.entries, key)
			}
		}
		if len(m.entries) >= streamLimit {
			for key, e := range m.entries {
				removeEntryFile(e)
				delete(m.entries, key)
				if len(m.entries) < streamLimit-16 {
					break
				}
			}
		}
	}
	m.entries[t] = entry
	return t
}

func removeEntryFile(e *streamEntry) {
	if e != nil && e.FilePath != "" {
		_ = os.Remove(e.FilePath)
	}
}

func (m *StreamManager) get(t string) (*streamEntry, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	e, ok := m.entries[t]
	if !ok {
		return nil, false
	}
	if time.Now().After(e.ExpiresAt) {
		removeEntryFile(e)
		delete(m.entries, t)
		return nil, false
	}
	return e, true
}

// Resolve turns song metadata into a local stream token. For providers whose
// audio is encrypted (Soda VIP, Migu Z3D) the file is fetched and decrypted up
// front, which is the same strategy go-music-dl uses for its web player.
func (m *StreamManager) Resolve(ctx context.Context, song model.Song) (*streamEntry, string, error) {
	if strings.TrimSpace(song.ID) == "" || strings.TrimSpace(song.Source) == "" {
		return nil, "", errors.New("missing song id or source")
	}
	source := song.Source
	cookie := m.store.Cookie(source)
	entry := &streamEntry{
		Song:    song,
		Headers: sourceHeaders(source),
		Ext:     strings.TrimSpace(song.Ext),
	}
	if cookie != "" {
		entry.Headers.Set("Cookie", cookie)
	}
	if song.Extra != nil {
		if song.Extra["preview_only"] == "true" || song.Extra["preview"] == "true" {
			entry.Preview = true
		}
	}
	if entry.Ext == "" {
		entry.Ext = "mp3"
	}

	switch source {
	case "soda":
		info, err := soda.New(cookie).GetDownloadInfo(&song)
		if err != nil {
			return nil, "", err
		}
		if strings.TrimSpace(info.PlayAuth) != "" {
			data, err := m.fetchBytes(ctx, info.URL, entry.Headers)
			if err != nil {
				return nil, "", err
			}
			data, err = soda.DecryptAudio(data, info.PlayAuth)
			if err != nil {
				return nil, "", err
			}
			ext := detectAudioExt(data)
			if ext == "" {
				ext = firstNonEmpty(info.Format, entry.Ext, "m4a")
			}
			path, err := m.writeTemp(data, ext)
			if err != nil {
				return nil, "", err
			}
			entry.FilePath, entry.Ext, entry.Preview = path, ext, info.Preview
		} else {
			entry.URL = info.URL
			entry.Ext = firstNonEmpty(info.Format, entry.Ext)
			entry.Preview = info.Preview
		}
	case "migu":
		info, err := migu.New(cookie).GetDownloadInfo(&song)
		if err != nil {
			return nil, "", err
		}
		if info.Encrypted {
			data, err := m.fetchBytes(ctx, info.URL, entry.Headers)
			if err != nil {
				return nil, "", err
			}
			data, err = migu.DecryptAudio(data, info.FileKey)
			if err != nil {
				return nil, "", err
			}
			ext := detectAudioExt(data)
			if ext == "" {
				ext = firstNonEmpty(info.Ext, info.Format, entry.Ext)
			}
			path, err := m.writeTemp(data, ext)
			if err != nil {
				return nil, "", err
			}
			entry.FilePath, entry.Ext = path, ext
		} else {
			entry.URL = info.URL
			entry.Ext = firstNonEmpty(info.Ext, info.Format, entry.Ext)
		}
	default:
		p, err := m.provider(source)
		if err != nil {
			return nil, "", err
		}
		if p.downloadURL == nil {
			return nil, "", errors.New("该平台不支持在线播放")
		}
		url, err := p.downloadURL(&song)
		if err != nil {
			return nil, "", err
		}
		if strings.TrimSpace(url) == "" {
			return nil, "", errors.New("平台没有返回播放地址")
		}
		entry.URL = url
	}
	if entry.ContentType == "" {
		entry.ContentType = mimeForExt(entry.Ext)
	}
	t := m.add(entry)
	return entry, t, nil
}

func (m *StreamManager) provider(source string) (*provider, error) {
	return newProvider(source, m.store.Cookie(source))
}

func (m *StreamManager) fetchBytes(ctx context.Context, url string, headers http.Header) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	for k, values := range headers {
		for _, v := range values {
			req.Header.Add(k, v)
		}
	}
	client := &http.Client{Timeout: 3 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("audio server returned HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 512<<20))
}

func (m *StreamManager) writeTemp(data []byte, ext string) (string, error) {
	dir := filepath.Join(m.dataDir, "stream_cache")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	if ext == "" {
		ext = "mp3"
	}
	path := filepath.Join(dir, token()+"."+strings.TrimPrefix(ext, "."))
	return path, os.WriteFile(path, data, 0o644)
}

func (m *StreamManager) Serve(w http.ResponseWriter, r *http.Request, t string) {
	entry, ok := m.get(t)
	if !ok {
		http.Error(w, "stream expired", http.StatusNotFound)
		return
	}
	if entry.FilePath != "" {
		f, err := os.Open(entry.FilePath)
		if err != nil {
			http.Error(w, "stream missing", http.StatusNotFound)
			return
		}
		defer f.Close()
		stat, err := f.Stat()
		if err != nil {
			http.Error(w, "stream missing", http.StatusNotFound)
			return
		}
		if entry.ContentType != "" {
			w.Header().Set("Content-Type", entry.ContentType)
		}
		w.Header().Set("Accept-Ranges", "bytes")
		w.Header().Set("Cache-Control", "no-store")
		http.ServeContent(w, r, filepath.Base(entry.FilePath), stat.ModTime(), f)
		return
	}
	req, err := http.NewRequestWithContext(r.Context(), r.Method, entry.URL, nil)
	if err != nil {
		http.Error(w, "invalid upstream url", http.StatusBadGateway)
		return
	}
	for k, values := range entry.Headers {
		for _, v := range values {
			req.Header.Add(k, v)
		}
	}
	if rangeHeader := r.Header.Get("Range"); rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}
	client := &http.Client{Timeout: 0}
	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	for _, key := range []string{"Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag"} {
		if v := resp.Header.Get(key); v != "" {
			w.Header().Set(key, v)
		}
	}
	if w.Header().Get("Content-Type") == "" && entry.ContentType != "" {
		w.Header().Set("Content-Type", entry.ContentType)
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func (m *StreamManager) Cleanup() {
	m.mu.Lock()
	defer m.mu.Unlock()
	for key, e := range m.entries {
		if time.Now().After(e.ExpiresAt) {
			removeEntryFile(e)
			delete(m.entries, key)
		}
	}
}

func detectAudioExt(data []byte) string {
	if len(data) < 4 {
		return ""
	}
	if len(data) >= 3 && string(data[:3]) == "ID3" {
		return "mp3"
	}
	switch {
	case len(data) >= 4 && string(data[:4]) == "fLaC":
		return "flac"
	case len(data) >= 4 && string(data[:4]) == "OggS":
		return "ogg"
	case len(data) >= 4 && string(data[:4]) == "RIFF":
		return "wav"
	case len(data) >= 8 && string(data[4:8]) == "ftyp":
		return "m4a"
	case len(data) >= 3 && string(data[:3]) == "ID3":
		return "mp3"
	case len(data) >= 2 && data[0] == 0xFF && data[1]&0xE0 == 0xE0:
		return "mp3"
	}
	return ""
}

func mimeForExt(ext string) string {
	switch strings.ToLower(strings.TrimPrefix(ext, ".")) {
	case "flac":
		return "audio/flac"
	case "m4a", "mp4", "aac":
		return "audio/mp4"
	case "ogg", "opus":
		return "audio/ogg"
	case "wav":
		return "audio/wav"
	case "wma":
		return "audio/x-ms-wma"
	default:
		return "audio/mpeg"
	}
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}
