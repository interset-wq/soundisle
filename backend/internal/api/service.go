package api

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/guohuiyuan/music-lib/model"
)

type SearchGroup struct {
	Source    string           `json:"source"`
	Name      string           `json:"name"`
	Songs     []model.Song     `json:"songs,omitempty"`
	Playlists []model.Playlist `json:"playlists,omitempty"`
	Error     string           `json:"error,omitempty"`
	TookMs    int64            `json:"tookMs"`
}

type SearchResponse struct {
	Query  string        `json:"query"`
	Type   string        `json:"type"`
	Groups []SearchGroup `json:"groups"`
	Total  int           `json:"total"`
	TookMs int64         `json:"tookMs"`
}

type DetailResponse struct {
	Type     string          `json:"type"`
	Playlist *model.Playlist `json:"playlist,omitempty"`
	Song     *model.Song     `json:"song,omitempty"`
	Songs    []model.Song    `json:"songs"`
}

type TopListGroup struct {
	Source string         `json:"source"`
	Name   string         `json:"name"`
	Lists  []model.TopList `json:"lists"`
	Error  string         `json:"error,omitempty"`
}

type CategoryGroup struct {
	Source     string                   `json:"source"`
	Name       string                   `json:"name"`
	Categories []model.PlaylistCategory `json:"categories"`
	Error      string                   `json:"error,omitempty"`
}

func (s *Service) provider(source string) (*provider, error) {
	if _, ok := sourceInfo(source); !ok {
		return nil, errors.New("unknown source: " + source)
	}
	return newProvider(source, s.Store.Cookie(source))
}

func normalizeSources(requested []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(requested))
	for _, raw := range requested {
		for _, part := range strings.Split(raw, ",") {
			id := strings.TrimSpace(part)
			if id == "" || seen[id] {
				continue
			}
			if _, ok := sourceInfo(id); !ok {
				continue
			}
			seen[id] = true
			out = append(out, id)
		}
	}
	return out
}

func (s *Service) Search(ctx context.Context, query, searchType string, sources []string, limit int) SearchResponse {
	started := time.Now()
	query = strings.TrimSpace(query)
	searchType = strings.TrimSpace(searchType)
	if searchType == "" {
		searchType = "song"
	}
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	sources = normalizeSources(sources)
	if len(sources) == 0 {
		sources = s.Store.Settings().DefaultSearch
	}
	resp := SearchResponse{Query: query, Type: searchType, Groups: make([]SearchGroup, len(sources))}
	if query == "" {
		resp.TookMs = time.Since(started).Milliseconds()
		return resp
	}

	var wg sync.WaitGroup
	for i, source := range sources {
		wg.Add(1)
		go func(i int, source string) {
			defer wg.Done()
			group := SearchGroup{Source: source, Name: source}
			groupStart := time.Now()
			p, err := s.provider(source)
			if err != nil {
				group.Error = err.Error()
				resp.Groups[i] = group
				return
			}
			group.Name = p.name
			ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
			defer cancel()
			done := make(chan struct{})
			var songs []model.Song
			var lists []model.Playlist
			var runErr error
			go func() {
				defer close(done)
				switch searchType {
				case "playlist":
					if p.searchList == nil {
						runErr = errors.New("该平台不支持歌单搜索")
						return
					}
					lists, runErr = p.searchList(query)
				case "album":
					if p.searchAlbum == nil {
						runErr = errors.New("该平台不支持专辑搜索")
						return
					}
					lists, runErr = p.searchAlbum(query)
				default:
					if p.search == nil {
						runErr = errors.New("该平台不支持歌曲搜索")
						return
					}
					songs, runErr = p.search(query)
				}
			}()
			select {
			case <-done:
			case <-ctx.Done():
				runErr = errors.New("搜索超时")
			}
			if runErr != nil {
				group.Error = runErr.Error()
			}
			if len(songs) > limit {
				songs = songs[:limit]
			}
			if len(lists) > limit {
				lists = lists[:limit]
			}
			for i := range songs {
				if songs[i].Source == "" {
					songs[i].Source = source
				}
			}
			for i := range lists {
				if lists[i].Source == "" {
					lists[i].Source = source
				}
			}
			group.Songs, group.Playlists = songs, lists
			group.TookMs = time.Since(groupStart).Milliseconds()
			resp.Groups[i] = group
		}(i, source)
	}
	wg.Wait()
	total := 0
	for _, g := range resp.Groups {
		total += len(g.Songs) + len(g.Playlists)
	}
	resp.Total = total
	resp.TookMs = time.Since(started).Milliseconds()
	return resp
}

func (s *Service) PlaylistSongs(source, id string) (DetailResponse, error) {
	p, err := s.provider(source)
	if err != nil {
		return DetailResponse{}, err
	}
	if p.listSongs == nil {
		return DetailResponse{}, errors.New("该平台不支持歌单")
	}
	songs, err := p.listSongs(id)
	if err != nil {
		return DetailResponse{}, err
	}
	normalizeSongSources(songs, source)
	return DetailResponse{Type: "playlist", Songs: songs, Playlist: &model.Playlist{ID: id, Source: source}}, nil
}

func (s *Service) AlbumSongs(source, id string) (DetailResponse, error) {
	p, err := s.provider(source)
	if err != nil {
		return DetailResponse{}, err
	}
	if p.albumSongs == nil {
		return DetailResponse{}, errors.New("该平台不支持专辑")
	}
	songs, err := p.albumSongs(id)
	if err != nil {
		return DetailResponse{}, err
	}
	normalizeSongSources(songs, source)
	return DetailResponse{Type: "album", Songs: songs, Playlist: &model.Playlist{ID: id, Source: source}}, nil
}

func normalizeSongSources(songs []model.Song, source string) {
	for i := range songs {
		if songs[i].Source == "" {
			songs[i].Source = source
		}
	}
}

func (s *Service) TopLists(ctx context.Context, sources []string) []TopListGroup {
	sources = normalizeSources(sources)
	if len(sources) == 0 {
		sources = []string{"netease", "qq", "kugou", "kuwo", "migu", "soda", "apple", "spotify"}
	}
	groups := make([]TopListGroup, len(sources))
	var wg sync.WaitGroup
	for i, source := range sources {
		wg.Add(1)
		go func(i int, source string) {
			defer wg.Done()
			g := TopListGroup{Source: source, Name: source}
			p, err := s.provider(source)
			if err != nil {
				g.Error = err.Error()
				groups[i] = g
				return
			}
			g.Name = p.name
			if p.topLists == nil {
				g.Error = "该平台不支持排行榜"
				groups[i] = g
				return
			}
			ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
			defer cancel()
			ch := make(chan struct{})
			go func() {
				defer close(ch)
				g.Lists, err = p.topLists()
			}()
			select {
			case <-ch:
			case <-ctx.Done():
				err = errors.New("请求超时")
			}
			if err != nil {
				g.Error = err.Error()
			}
			groups[i] = g
		}(i, source)
	}
	wg.Wait()
	return groups
}

func (s *Service) TopListSongs(source, id string) ([]model.Song, error) {
	p, err := s.provider(source)
	if err != nil {
		return nil, err
	}
	if p.topListSongs == nil {
		return nil, errors.New("该平台不支持排行榜")
	}
	songs, err := p.topListSongs(id)
	if err != nil {
		return nil, err
	}
	normalizeSongSources(songs, source)
	return songs, nil
}

func (s *Service) Categories(ctx context.Context, sources []string) []CategoryGroup {
	sources = normalizeSources(sources)
	if len(sources) == 0 {
		sources = []string{"netease", "qq", "kugou", "kuwo", "migu", "qianqian", "joox", "soda", "apple", "spotify"}
	}
	groups := make([]CategoryGroup, len(sources))
	var wg sync.WaitGroup
	for i, source := range sources {
		wg.Add(1)
		go func(i int, source string) {
			defer wg.Done()
			g := CategoryGroup{Source: source, Name: source}
			p, err := s.provider(source)
			if err != nil {
				g.Error = err.Error()
				groups[i] = g
				return
			}
			g.Name = p.name
			if p.categories == nil {
				g.Error = "该平台不支持歌单分类"
				groups[i] = g
				return
			}
			ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
			defer cancel()
			ch := make(chan struct{})
			go func() {
				defer close(ch)
				g.Categories, err = p.categories()
			}()
			select {
			case <-ch:
			case <-ctx.Done():
				err = errors.New("请求超时")
			}
			if err != nil {
				g.Error = err.Error()
			}
			groups[i] = g
		}(i, source)
	}
	wg.Wait()
	return groups
}

func (s *Service) CategoryPlaylists(source, categoryID string, page, limit int) ([]model.Playlist, error) {
	p, err := s.provider(source)
	if err != nil {
		return nil, err
	}
	if p.catPlaylists == nil {
		return nil, errors.New("该平台不支持歌单分类")
	}
	if page <= 0 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	lists, err := p.catPlaylists(categoryID, page, limit)
	if err != nil {
		return nil, err
	}
	for i := range lists {
		if lists[i].Source == "" {
			lists[i].Source = source
		}
	}
	return lists, nil
}

func (s *Service) Recommend(source string) ([]model.Playlist, error) {
	p, err := s.provider(source)
	if err != nil {
		return nil, err
	}
	if p.recommend == nil {
		return nil, errors.New("该平台不支持推荐歌单")
	}
	lists, err := p.recommend()
	if err != nil {
		return nil, err
	}
	for i := range lists {
		if lists[i].Source == "" {
			lists[i].Source = source
		}
	}
	return lists, nil
}

func (s *Service) HotSongs(source string, limit int) ([]model.Song, error) {
	p, err := s.provider(source)
	if err != nil {
		return nil, err
	}
	if p.hotSongs == nil {
		return nil, errors.New("该平台不支持热门单曲")
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	songs, err := p.hotSongs(limit)
	if err != nil {
		return nil, err
	}
	normalizeSongSources(songs, source)
	return songs, nil
}

func (s *Service) Lyrics(source string, song model.Song) (string, error) {
	p, err := s.provider(source)
	if err != nil {
		return "", err
	}
	if p.lyric == nil {
		return "", errors.New("该平台不支持歌词")
	}
	if song.Source == "" {
		song.Source = source
	}
	return p.lyric(&song)
}

func (s *Service) UserPlaylists(source string) ([]model.Playlist, error) {
	p, err := s.provider(source)
	if err != nil {
		return nil, err
	}
	if p.userPlaylists == nil {
		return nil, errors.New("该平台不支持个人歌单")
	}
	lists, err := p.userPlaylists(1, 100)
	if err != nil {
		return nil, err
	}
	for i := range lists {
		if lists[i].Source == "" {
			lists[i].Source = source
		}
	}
	return lists, nil
}

// DetectSource maps a share link to a provider id.
func DetectSource(link string) string {
	link = strings.ToLower(strings.TrimSpace(link))
	switch {
	case strings.Contains(link, "music.163.com") || strings.Contains(link, "163cn.tv"):
		return "netease"
	case strings.Contains(link, "y.qq.com") || strings.Contains(link, "c6.y.qq.com") || strings.Contains(link, "i.y.qq.com"):
		return "qq"
	case strings.Contains(link, "kugou.com"):
		return "kugou"
	case strings.Contains(link, "kuwo.cn"):
		return "kuwo"
	case strings.Contains(link, "music.migu.cn") || strings.Contains(link, "m.migu.cn"):
		return "migu"
	case strings.Contains(link, "music.taihe.com") || strings.Contains(link, "qianqian.com"):
		return "qianqian"
	case strings.Contains(link, "qishui.douyin.com") || strings.Contains(link, "music.douyin.com"):
		return "soda"
	case strings.Contains(link, "bilibili.com") || strings.Contains(link, "b23.tv"):
		return "bilibili"
	case strings.Contains(link, "joox.com"):
		return "joox"
	case strings.Contains(link, "jamendo.com"):
		return "jamendo"
	case strings.Contains(link, "5sing.kugou.com") || strings.Contains(link, "5sing.com"):
		return "fivesing"
	case strings.Contains(link, "music.apple.com"):
		return "apple"
	case strings.Contains(link, "spotify.com"):
		return "spotify"
	}
	return ""
}

func (s *Service) ParseLink(link string) (DetailResponse, error) {
	link = strings.TrimSpace(link)
	if link == "" {
		return DetailResponse{}, errors.New("link is required")
	}
	source := DetectSource(link)
	if source == "" {
		return DetailResponse{}, errors.New("无法识别链接来源")
	}
	p, err := s.provider(source)
	if err != nil {
		return DetailResponse{}, err
	}
	// Try playlist, then album, then a single song. Platforms return errors or
	// empty data for links that do not belong to that content type.
	if pi, ok := p.instance.(interface {
		ParsePlaylist(string) (*model.Playlist, []model.Song, error)
	}); ok {
		if pl, songs, err := pi.ParsePlaylist(link); err == nil && pl != nil {
			if pl.Source == "" {
				pl.Source = source
			}
			normalizeSongSources(songs, source)
			if len(songs) > 0 {
				return DetailResponse{Type: "playlist", Playlist: pl, Songs: songs}, nil
			}
		}
	}
	if ai, ok := p.instance.(interface {
		ParseAlbum(string) (*model.Playlist, []model.Song, error)
	}); ok {
		if al, songs, err := ai.ParseAlbum(link); err == nil && al != nil {
			if al.Source == "" {
				al.Source = source
			}
			normalizeSongSources(songs, source)
			if len(songs) > 0 {
				return DetailResponse{Type: "album", Playlist: al, Songs: songs}, nil
			}
		}
	}
	if si, ok := p.instance.(interface {
		Parse(string) (*model.Song, error)
	}); ok {
		if song, err := si.Parse(link); err == nil && song != nil {
			if song.Source == "" {
				song.Source = source
			}
			return DetailResponse{Type: "song", Song: song, Songs: []model.Song{*song}}, nil
		}
	}
	return DetailResponse{}, fmt.Errorf("无法解析该 %s 链接", source)
}

func sortSongsByRank(songs []model.Song) {
	sort.SliceStable(songs, func(i, j int) bool {
		ri, rj := songs[i].Extra["rank"], songs[j].Extra["rank"]
		if ri == "" || rj == "" {
			return false
		}
		return ri < rj
	})
}
