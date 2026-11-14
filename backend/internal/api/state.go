package api

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/guohuiyuan/music-lib/model"
)

// Settings are user preferences that belong to this installation.
type Settings struct {
	DownloadDir       string `json:"downloadDir"`
	FilenameTemplate  string `json:"filenameTemplate"`
	EmbedLyrics       bool   `json:"embedLyrics"`
	DefaultSearch     []string `json:"defaultSearchSources"`
	PreferredQuality  string `json:"preferredQuality"`
	ThemeMode         string `json:"themeMode"`
}

// Collection is a user-created playlist or the built-in favorites list.
type Collection struct {
	ID        string       `json:"id"`
	Name      string       `json:"name"`
	Cover     string       `json:"cover"`
	IsFav     bool         `json:"isFavorites"`
	Songs     []model.Song `json:"songs"`
	CreatedAt time.Time    `json:"createdAt"`
	UpdatedAt time.Time    `json:"updatedAt"`
}

type persistedState struct {
	Cookies     map[string]string `json:"cookies"`
	Settings    Settings          `json:"settings"`
	Collections []Collection      `json:"collections"`
}

// Store is a small JSON-backed persistence layer. It intentionally avoids
// SQLite/cgo so the exact same code can run on Android, iOS and desktop.
type Store struct {
	mu    sync.RWMutex
	path  string
	state persistedState
}

func OpenStore(dataDir string) (*Store, error) {
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, err
	}
	s := &Store{path: filepath.Join(dataDir, "state.json")}
	s.state = persistedState{
		Cookies: map[string]string{},
		Settings: Settings{
			DownloadDir:      filepath.Join(dataDir, "downloads"),
			FilenameTemplate: "{artist} - {name}",
			EmbedLyrics:      true,
			DefaultSearch:    append([]string(nil), defaultSearchSources...),
			PreferredQuality: "best",
			ThemeMode:        "system",
		},
	}
	if raw, err := os.ReadFile(s.path); err == nil && len(raw) > 0 {
		if err := json.Unmarshal(raw, &s.state); err != nil {
			return nil, err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if s.state.Cookies == nil {
		s.state.Cookies = map[string]string{}
	}
	if strings.TrimSpace(s.state.Settings.DownloadDir) == "" {
		s.state.Settings.DownloadDir = filepath.Join(dataDir, "downloads")
	}
	if strings.TrimSpace(s.state.Settings.FilenameTemplate) == "" {
		s.state.Settings.FilenameTemplate = "{artist} - {name}"
	}
	if len(s.state.Settings.DefaultSearch) == 0 {
		s.state.Settings.DefaultSearch = append([]string(nil), defaultSearchSources...)
	}
	if err := os.MkdirAll(s.state.Settings.DownloadDir, 0o755); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) saveLocked() error {
	raw, err := json.MarshalIndent(s.state, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

func (s *Store) Save() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.saveLocked()
}

func (s *Store) Cookie(source string) string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.state.Cookies[source]
}

func (s *Store) Cookies() map[string]string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make(map[string]string, len(s.state.Cookies))
	for k, v := range s.state.Cookies {
		out[k] = v
	}
	return out
}

func (s *Store) SetCookie(source, value string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	source = strings.TrimSpace(source)
	if source == "" {
		return errors.New("source is required")
	}
	value = strings.TrimSpace(value)
	if value == "" {
		delete(s.state.Cookies, source)
	} else {
		s.state.Cookies[source] = value
	}
	return s.saveLocked()
}

func (s *Store) Settings() Settings {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := s.state.Settings
	out.DefaultSearch = append([]string(nil), s.state.Settings.DefaultSearch...)
	return out
}

func (s *Store) UpdateSettings(next Settings) (Settings, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	next.DownloadDir = strings.TrimSpace(next.DownloadDir)
	if next.DownloadDir == "" {
		next.DownloadDir = s.state.Settings.DownloadDir
	}
	next.FilenameTemplate = strings.TrimSpace(next.FilenameTemplate)
	if next.FilenameTemplate == "" {
		next.FilenameTemplate = "{artist} - {name}"
	}
	if len(next.DefaultSearch) == 0 {
		next.DefaultSearch = append([]string(nil), defaultSearchSources...)
	}
	if err := os.MkdirAll(next.DownloadDir, 0o755); err != nil {
		return Settings{}, err
	}
	s.state.Settings = next
	if err := s.saveLocked(); err != nil {
		return Settings{}, err
	}
	return next, nil
}

func (s *Store) Collections() []Collection {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Collection, len(s.state.Collections))
	for i, c := range s.state.Collections {
		out[i] = cloneCollection(c)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].IsFav != out[j].IsFav {
			return out[i].IsFav
		}
		return out[i].UpdatedAt.After(out[j].UpdatedAt)
	})
	return out
}

func cloneCollection(c Collection) Collection {
	c.Songs = append([]model.Song(nil), c.Songs...)
	return c
}

func (s *Store) Collection(id string) (Collection, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, c := range s.state.Collections {
		if c.ID == id {
			return cloneCollection(c), true
		}
	}
	if id == "favorites" {
		return Collection{ID: "favorites", Name: "我喜欢的音乐", IsFav: true}, true
	}
	return Collection{}, false
}

func (s *Store) ensureFavoritesLocked() *Collection {
	for i := range s.state.Collections {
		if s.state.Collections[i].ID == "favorites" {
			return &s.state.Collections[i]
		}
	}
	now := time.Now()
	c := Collection{ID: "favorites", Name: "我喜欢的音乐", IsFav: true, CreatedAt: now, UpdatedAt: now}
	s.state.Collections = append([]Collection{c}, s.state.Collections...)
	return &s.state.Collections[0]
}

func (s *Store) CreateCollection(name string) (Collection, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	name = strings.TrimSpace(name)
	if name == "" {
		return Collection{}, errors.New("name is required")
	}
	now := time.Now()
	c := Collection{ID: newID("pl"), Name: name, CreatedAt: now, UpdatedAt: now}
	s.state.Collections = append(s.state.Collections, c)
	if err := s.saveLocked(); err != nil {
		return Collection{}, err
	}
	return cloneCollection(c), nil
}

func (s *Store) RenameCollection(id, name string) (Collection, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if id == "favorites" {
		return Collection{}, errors.New("favorites cannot be renamed")
	}
	for i := range s.state.Collections {
		if s.state.Collections[i].ID == id {
			s.state.Collections[i].Name = strings.TrimSpace(name)
			s.state.Collections[i].UpdatedAt = time.Now()
			if err := s.saveLocked(); err != nil {
				return Collection{}, err
			}
			return cloneCollection(s.state.Collections[i]), nil
		}
	}
	return Collection{}, errors.New("collection not found")
}

func (s *Store) DeleteCollection(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if id == "favorites" {
		return errors.New("favorites cannot be deleted")
	}
	for i := range s.state.Collections {
		if s.state.Collections[i].ID == id {
			s.state.Collections = append(s.state.Collections[:i], s.state.Collections[i+1:]...)
			return s.saveLocked()
		}
	}
	return errors.New("collection not found")
}

func sameSong(a, b model.Song) bool {
	return a.Source == b.Source && a.ID == b.ID
}

func (s *Store) AddSongs(id string, songs []model.Song) (Collection, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var target *Collection
	if id == "favorites" {
		target = s.ensureFavoritesLocked()
	} else {
		for i := range s.state.Collections {
			if s.state.Collections[i].ID == id {
				target = &s.state.Collections[i]
				break
			}
		}
	}
	if target == nil {
		return Collection{}, errors.New("collection not found")
	}
	for _, song := range songs {
		if strings.TrimSpace(song.ID) == "" || strings.TrimSpace(song.Source) == "" {
			continue
		}
		exists := false
		for _, existing := range target.Songs {
			if sameSong(existing, song) {
				exists = true
				break
			}
		}
		if !exists {
			target.Songs = append(target.Songs, song)
		}
	}
	target.UpdatedAt = time.Now()
	if target.Cover == "" && len(target.Songs) > 0 {
		target.Cover = target.Songs[0].Cover
	}
	if err := s.saveLocked(); err != nil {
		return Collection{}, err
	}
	return cloneCollection(*target), nil
}

func (s *Store) RemoveSong(id, source, songID string) (Collection, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var target *Collection
	if id == "favorites" {
		target = s.ensureFavoritesLocked()
	} else {
		for i := range s.state.Collections {
			if s.state.Collections[i].ID == id {
				target = &s.state.Collections[i]
				break
			}
		}
	}
	if target == nil {
		return Collection{}, errors.New("collection not found")
	}
	out := target.Songs[:0]
	for _, song := range target.Songs {
		if song.Source == source && song.ID == songID {
			continue
		}
		out = append(out, song)
	}
	target.Songs = out
	target.UpdatedAt = time.Now()
	if err := s.saveLocked(); err != nil {
		return Collection{}, err
	}
	return cloneCollection(*target), nil
}

func (s *Store) IsFavorite(source, songID string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, c := range s.state.Collections {
		if c.ID != "favorites" {
			continue
		}
		for _, song := range c.Songs {
			if song.Source == source && song.ID == songID {
				return true
			}
		}
	}
	return false
}

func newID(prefix string) string {
	buf := make([]byte, 8)
	_, _ = rand.Read(buf)
	return prefix + "_" + hex.EncodeToString(buf)
}
