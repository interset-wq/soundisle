package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/guohuiyuan/music-lib/bilibili"
	"github.com/guohuiyuan/music-lib/kugou"
	"github.com/guohuiyuan/music-lib/model"
	"github.com/guohuiyuan/music-lib/netease"
	"github.com/guohuiyuan/music-lib/qq"
)

type Service struct {
	DataDir   string
	Token     string
	Store     *Store
	Streams   *StreamManager
	Library   *Library
	Downloads *DownloadManager
	startedAt time.Time
}

func NewService(dataDir, token string) (*Service, error) {
	store, err := OpenStore(dataDir)
	if err != nil {
		return nil, err
	}
	streams := NewStreamManager(dataDir, store)
	library := NewLibrary(dataDir, store)
	s := &Service{
		DataDir: dataDir, Token: token, Store: store, Streams: streams, Library: library,
		Downloads: NewDownloadManager(store, streams), startedAt: time.Now(),
	}
	_, _ = library.Scan()
	return s, nil
}

func (s *Service) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", s.handleHealth)
	mux.HandleFunc("GET /api/sources", s.handleSources)
	mux.HandleFunc("GET /api/settings", s.handleSettings)
	mux.HandleFunc("PUT /api/settings", s.handleUpdateSettings)
	mux.HandleFunc("GET /api/cookies", s.handleCookies)
	mux.HandleFunc("PUT /api/cookies", s.handleCookies)
	mux.HandleFunc("GET /api/search", s.handleSearch)
	mux.HandleFunc("GET /api/playlist", s.handlePlaylist)
	mux.HandleFunc("GET /api/album", s.handleAlbum)
	mux.HandleFunc("GET /api/toplists", s.handleTopLists)
	mux.HandleFunc("GET /api/toplist", s.handleTopListSongs)
	mux.HandleFunc("GET /api/categories", s.handleCategories)
	mux.HandleFunc("GET /api/category", s.handleCategory)
	mux.HandleFunc("GET /api/recommend", s.handleRecommend)
	mux.HandleFunc("GET /api/user_playlists", s.handleUserPlaylists)
	mux.HandleFunc("GET /api/hot", s.handleHotSongs)
	mux.HandleFunc("GET /api/parse", s.handleParse)
	mux.HandleFunc("POST /api/lyric", s.handleLyric)
	mux.HandleFunc("POST /api/play", s.handlePlay)
	mux.HandleFunc("GET /api/stream/{token}", s.handleStream)
	mux.HandleFunc("GET /api/cover", s.handleCover)
	mux.HandleFunc("GET /api/library", s.handleLibrary)
	mux.HandleFunc("POST /api/library/scan", s.handleScan)
	mux.HandleFunc("GET /api/library/stream", s.handleLibraryStream)
	mux.HandleFunc("GET /api/library/cover", s.handleLibraryCover)
	mux.HandleFunc("DELETE /api/library", s.handleLibraryDelete)
	mux.HandleFunc("POST /api/library/delete", s.handleLibraryDeleteMany)
	mux.HandleFunc("POST /api/download", s.handleDownload)
	mux.HandleFunc("GET /api/downloads", s.handleDownloads)
	mux.HandleFunc("DELETE /api/downloads/{id}", s.handleDeleteDownload)
	mux.HandleFunc("POST /api/downloads/{id}/retry", s.handleRetryDownload)
	mux.HandleFunc("GET /api/collections", s.handleCollections)
	mux.HandleFunc("POST /api/collections", s.handleCollections)
	mux.HandleFunc("GET /api/collections/{id}", s.handleCollection)
	mux.HandleFunc("PATCH /api/collections/{id}", s.handleCollection)
	mux.HandleFunc("DELETE /api/collections/{id}", s.handleCollection)
	mux.HandleFunc("POST /api/collections/{id}/songs", s.handleCollectionSongs)
	mux.HandleFunc("DELETE /api/collections/{id}/songs", s.handleCollectionSongs)
	mux.HandleFunc("POST /api/login/{source}/create", s.handleLoginCreate)
	mux.HandleFunc("POST /api/login/{source}/check", s.handleLoginCheck)
	return s.withAuth(mux)
}

func (s *Service) withAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		// Stream and embedded-local-file URLs carry their own capability token or
		// are only reachable from the loopback interface (audio players cannot
		// always attach custom headers).
		if strings.HasPrefix(path, "/api/stream/") || path == "/api/library/stream" {
			next.ServeHTTP(w, r)
			return
		}
		if path == "/api/health" {
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "version": Version, "uptime": time.Since(s.startedAt).Seconds()})
			return
		}
		token := r.Header.Get("X-Music-Token")
		if token == "" {
			token = r.URL.Query().Get("token")
		}
		if token == "" || token != s.Token {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next.ServeHTTP(w, r)
	})
}

const Version = "0.1.0"

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func decodeJSON(r *http.Request, dst any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(io.LimitReader(r.Body, 4<<20))
	return dec.Decode(dst)
}

func (s *Service) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "version": Version})
}

func (s *Service) handleSources(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"sources":  SourceInfos(),
		"defaults": s.Store.Settings().DefaultSearch,
	})
}

func (s *Service) handleSettings(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.Store.Settings())
}

func (s *Service) handleUpdateSettings(w http.ResponseWriter, r *http.Request) {
	var next Settings
	if err := decodeJSON(r, &next); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	updated, err := s.Store.UpdateSettings(next)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func (s *Service) handleCookies(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		writeJSON(w, http.StatusOK, map[string]any{"cookies": s.Store.Cookies()})
		return
	}
	var payload struct {
		Source string `json:"source"`
		Value  string `json:"value"`
	}
	if err := decodeJSON(r, &payload); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := s.Store.SetCookie(payload.Source, payload.Value); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Service) handleSearch(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	sources := q["sources"]
	if len(sources) == 0 {
		sources = q["source"]
	}
	limit, _ := strconv.Atoi(q.Get("limit"))
	resp := s.Search(r.Context(), q.Get("q"), q.Get("type"), sources, limit)
	writeJSON(w, http.StatusOK, resp)
}

func (s *Service) handlePlaylist(w http.ResponseWriter, r *http.Request) {
	source, id := r.URL.Query().Get("source"), r.URL.Query().Get("id")
	if source == "" || id == "" {
		writeError(w, http.StatusBadRequest, "source and id are required")
		return
	}
	detail, err := s.PlaylistSongs(source, id)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, detail)
}

func (s *Service) handleAlbum(w http.ResponseWriter, r *http.Request) {
	source, id := r.URL.Query().Get("source"), r.URL.Query().Get("id")
	if source == "" || id == "" {
		writeError(w, http.StatusBadRequest, "source and id are required")
		return
	}
	detail, err := s.AlbumSongs(source, id)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, detail)
}

func (s *Service) handleTopLists(w http.ResponseWriter, r *http.Request) {
	sources := r.URL.Query()["sources"]
	writeJSON(w, http.StatusOK, map[string]any{"groups": s.TopLists(r.Context(), sources)})
}

func (s *Service) handleTopListSongs(w http.ResponseWriter, r *http.Request) {
	source, id := r.URL.Query().Get("source"), r.URL.Query().Get("id")
	if id == "" {
		id = r.URL.Query().Get("toplist_id")
	}
	if source == "" || id == "" {
		writeError(w, http.StatusBadRequest, "source and id are required")
		return
	}
	songs, err := s.TopListSongs(source, id)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"songs": songs, "total": len(songs)})
}

func (s *Service) handleCategories(w http.ResponseWriter, r *http.Request) {
	sources := r.URL.Query()["sources"]
	writeJSON(w, http.StatusOK, map[string]any{"groups": s.Categories(r.Context(), sources)})
}

func (s *Service) handleCategory(w http.ResponseWriter, r *http.Request) {
	source, id := r.URL.Query().Get("source"), r.URL.Query().Get("id")
	if id == "" {
		id = r.URL.Query().Get("category_id")
	}
	if source == "" || id == "" {
		writeError(w, http.StatusBadRequest, "source and id are required")
		return
	}
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	lists, err := s.CategoryPlaylists(source, id, page, limit)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": lists, "total": len(lists)})
}

func (s *Service) handleRecommend(w http.ResponseWriter, r *http.Request) {
	source := r.URL.Query().Get("source")
	if source == "" {
		source = "netease"
	}
	lists, err := s.Recommend(source)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": lists, "total": len(lists)})
}

func (s *Service) handleUserPlaylists(w http.ResponseWriter, r *http.Request) {
	source := r.URL.Query().Get("source")
	lists, err := s.UserPlaylists(source)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": lists})
}

func (s *Service) handleHotSongs(w http.ResponseWriter, r *http.Request) {
	source := r.URL.Query().Get("source")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	songs, err := s.HotSongs(source, limit)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"songs": songs})
}

func (s *Service) handleParse(w http.ResponseWriter, r *http.Request) {
	detail, err := s.ParseLink(r.URL.Query().Get("url"))
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, detail)
}

type songRequest struct {
	Song model.Song `json:"song"`
}

func (s *Service) handleLyric(w http.ResponseWriter, r *http.Request) {
	var req songRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Song.Source == "" {
		req.Song.Source = r.URL.Query().Get("source")
	}
	lrc, err := s.Lyrics(req.Song.Source, req.Song)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"lrc": lrc})
}

func (s *Service) handlePlay(w http.ResponseWriter, r *http.Request) {
	var req songRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Minute)
	defer cancel()
	entry, token, err := s.Streams.Resolve(ctx, req.Song)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"url":            "/api/stream/" + token,
		"ext":            entry.Ext,
		"preview":        entry.Preview,
		"expiresIn":      int(streamTTL.Seconds()),
		"source":         req.Song.Source,
		"fallback":       entry.FallbackSource != "",
		"resolvedSource": entry.FallbackSource,
		"resolvedName":   entry.FallbackName,
		"resolvedArtist": entry.FallbackArtist,
	})
}

func (s *Service) handleStream(w http.ResponseWriter, r *http.Request) {
	s.Streams.Serve(w, r, r.PathValue("token"))
}

func (s *Service) handleCover(w http.ResponseWriter, r *http.Request) {
	raw := r.URL.Query().Get("url")
	source := r.URL.Query().Get("source")
	if raw == "" {
		http.Error(w, "url is required", http.StatusBadRequest)
		return
	}
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		http.Error(w, "invalid url", http.StatusBadRequest)
		return
	}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, raw, nil)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	for k, values := range sourceHeaders(source) {
		for _, v := range values {
			req.Header.Add(k, v)
		}
	}
	if cookie := s.Store.Cookie(source); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		http.Error(w, "cover fetch failed", http.StatusBadGateway)
		return
	}
	if ct := resp.Header.Get("Content-Type"); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	w.Header().Set("Cache-Control", "public, max-age=86400")
	_, _ = io.Copy(w, io.LimitReader(resp.Body, 12<<20))
}

func (s *Service) handleLibrary(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	songs := s.Library.Songs(query, offset, limit)
	writeJSON(w, http.StatusOK, map[string]any{"songs": songs, "total": s.Library.Count()})
}

func (s *Service) handleScan(w http.ResponseWriter, r *http.Request) {
	songs, err := s.Library.Scan()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"songs": songs, "total": len(songs)})
}

func (s *Service) handleLibraryStream(w http.ResponseWriter, r *http.Request) {
	s.Library.ServeFile(w, r)
}

func (s *Service) handleLibraryCover(w http.ResponseWriter, r *http.Request) {
	s.Library.ServeCover(w, r)
}

func (s *Service) handleLibraryDelete(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		writeError(w, http.StatusBadRequest, "path is required")
		return
	}
	if err := s.Library.Delete(path); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// handleLibraryDeleteMany backs multi-select deletion in the local library.
func (s *Service) handleLibraryDeleteMany(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Paths []string `json:"paths"`
	}
	if err := decodeJSON(r, &payload); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if len(payload.Paths) == 0 {
		writeError(w, http.StatusBadRequest, "paths is required")
		return
	}
	if len(payload.Paths) > 500 {
		writeError(w, http.StatusBadRequest, "一次最多删除 500 首")
		return
	}
	deleted, failed := s.Library.DeleteMany(payload.Paths)
	writeJSON(w, http.StatusOK, map[string]any{"deleted": deleted, "failed": failed})
}

func (s *Service) handleDownload(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Songs []model.Song `json:"songs"`
		Song  *model.Song  `json:"song"`
	}
	if err := decodeJSON(r, &payload); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if payload.Song != nil {
		payload.Songs = append(payload.Songs, *payload.Song)
	}
	if len(payload.Songs) == 0 {
		writeError(w, http.StatusBadRequest, "songs is required")
		return
	}
	tasks := s.Downloads.Enqueue(payload.Songs)
	writeJSON(w, http.StatusAccepted, map[string]any{"tasks": tasks, "total": len(tasks)})
}

func (s *Service) handleDownloads(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"tasks": s.Downloads.List()})
}

func (s *Service) handleDeleteDownload(w http.ResponseWriter, r *http.Request) {
	s.Downloads.Remove(r.PathValue("id"))
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// handleRetryDownload re-queues a task that failed or was interrupted by the
// app being killed, so the user does not have to search for the song again.
func (s *Service) handleRetryDownload(w http.ResponseWriter, r *http.Request) {
	task, err := s.Downloads.Retry(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, task)
}

func (s *Service) handleCollections(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{"collections": s.Store.Collections()})
	case http.MethodPost:
		var payload struct {
			Name string `json:"name"`
		}
		if err := decodeJSON(r, &payload); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		c, err := s.Store.CreateCollection(payload.Name)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, c)
	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func (s *Service) handleCollection(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	switch r.Method {
	case http.MethodGet:
		c, ok := s.Store.Collection(id)
		if !ok {
			writeError(w, http.StatusNotFound, "collection not found")
			return
		}
		writeJSON(w, http.StatusOK, c)
	case http.MethodPatch:
		var payload struct {
			Name string `json:"name"`
		}
		if err := decodeJSON(r, &payload); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		c, err := s.Store.RenameCollection(id, payload.Name)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, c)
	case http.MethodDelete:
		if err := s.Store.DeleteCollection(id); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

func (s *Service) handleCollectionSongs(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if r.Method == http.MethodDelete {
		source := r.URL.Query().Get("source")
		songID := r.URL.Query().Get("id")
		c, err := s.Store.RemoveSong(id, source, songID)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, c)
		return
	}
	var payload struct {
		Songs []model.Song `json:"songs"`
		Song  *model.Song  `json:"song"`
	}
	if err := decodeJSON(r, &payload); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if payload.Song != nil {
		payload.Songs = append(payload.Songs, *payload.Song)
	}
	c, err := s.Store.AddSongs(id, payload.Songs)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, c)
}

type qrSessionResponse struct {
	Source   string            `json:"source"`
	Key      string            `json:"key"`
	ImageURL string            `json:"imageUrl"`
	URL      string            `json:"url"`
	Expires  int64             `json:"expiresAt"`
	Extra    map[string]string `json:"extra,omitempty"`
}

type qrResultResponse struct {
	Source  string `json:"source"`
	Status  string `json:"status"`
	Message string `json:"message"`
	Cookie  string `json:"cookie,omitempty"`
}

func (s *Service) qrProvider(source, loginType string) (interface {
	CreateQRLogin() (*model.QRLoginSession, error)
	CheckQRLogin(string) (*model.QRLoginResult, error)
}, error) {
	cookie := s.Store.Cookie(source)
	switch source {
	case "netease":
		return netease.New(cookie), nil
	case "kugou":
		return kugou.New(cookie), nil
	case "bilibili":
		return bilibili.New(cookie), nil
	case "qq":
		q := qq.New(cookie)
		if loginType == "wx" {
			return &wxQR{q}, nil
		}
		return q, nil
	default:
		return nil, errors.New("该平台不支持扫码登录")
	}
}

type wxQR struct{ q *qq.QQ }

func (w *wxQR) CreateQRLogin() (*model.QRLoginSession, error) { return w.q.CreateWXQRLogin() }
func (w *wxQR) CheckQRLogin(key string) (*model.QRLoginResult, error) {
	return w.q.CheckWXQRLogin(key)
}

func (s *Service) handleLoginCreate(w http.ResponseWriter, r *http.Request) {
	source := r.PathValue("source")
	loginType := r.URL.Query().Get("type")
	p, err := s.qrProvider(source, loginType)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	session, err := p.CreateQRLogin()
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, qrSessionResponse{
		Source: session.Source, Key: session.Key, ImageURL: session.ImageURL,
		URL: session.URL, Expires: session.ExpiresAt, Extra: session.Extra,
	})
}

func (s *Service) handleLoginCheck(w http.ResponseWriter, r *http.Request) {
	source := r.PathValue("source")
	loginType := r.URL.Query().Get("type")
	key := r.URL.Query().Get("key")
	if key == "" {
		writeError(w, http.StatusBadRequest, "key is required")
		return
	}
	p, err := s.qrProvider(source, loginType)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	result, err := p.CheckQRLogin(key)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	if result.Status == model.QRLoginStatusSuccess && strings.TrimSpace(result.Cookie) != "" {
		_ = s.Store.SetCookie(source, result.Cookie)
	}
	writeJSON(w, http.StatusOK, qrResultResponse{
		Source: result.Source, Status: string(result.Status),
		Message: result.Message, Cookie: result.Cookie,
	})
}

// Start binds to a loopback port and serves until the process exits.
func (s *Service) Start(addr string) (net.Listener, error) {
	if addr == "" {
		addr = "127.0.0.1:0"
	}
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}
	server := &http.Server{
		Handler:           s.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		_ = server.Serve(listener)
	}()
	go func() {
		ticker := time.NewTicker(10 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			s.Streams.Cleanup()
		}
	}()
	return listener, nil
}

func (s *Service) Port(listener net.Listener) int {
	if addr, ok := listener.Addr().(*net.TCPAddr); ok {
		return addr.Port
	}
	return 0
}

// EnsureDownloadDir is used by mobile shells that need a system music folder.
func ensureDir(path string) error {
	if path == "" {
		return nil
	}
	return os.MkdirAll(filepath.Clean(path), 0o755)
}

var _ = ensureDir
var _ = fmt.Sprintf
