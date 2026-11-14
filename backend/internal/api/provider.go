package api

import (
	"errors"

	"github.com/guohuiyuan/music-lib/apple"
	"github.com/guohuiyuan/music-lib/bilibili"
	"github.com/guohuiyuan/music-lib/fivesing"
	"github.com/guohuiyuan/music-lib/jamendo"
	"github.com/guohuiyuan/music-lib/joox"
	"github.com/guohuiyuan/music-lib/kugou"
	"github.com/guohuiyuan/music-lib/kuwo"
	"github.com/guohuiyuan/music-lib/migu"
	"github.com/guohuiyuan/music-lib/model"
	"github.com/guohuiyuan/music-lib/netease"
	"github.com/guohuiyuan/music-lib/qianqian"
	"github.com/guohuiyuan/music-lib/qq"
	"github.com/guohuiyuan/music-lib/soda"
	"github.com/guohuiyuan/music-lib/spotify"
)

// SourceInfo describes one upstream music provider and the capabilities the UI
// can rely on. Keep this in sync with music-lib's README.
type SourceInfo struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	Search       bool   `json:"search"`
	Playlist     bool   `json:"playlist"`
	Album        bool   `json:"album"`
	TopList      bool   `json:"topList"`
	Category     bool   `json:"category"`
	Recommend    bool   `json:"recommend"`
	UserPlaylist bool   `json:"userPlaylist"`
	QRLogin      bool   `json:"qrLogin"`
	Note         string `json:"note,omitempty"`
}

var sourceInfos = []SourceInfo{
	{ID: "netease", Name: "网易云音乐", Search: true, Playlist: true, Album: true, TopList: true, Category: true, Recommend: true, UserPlaylist: true, QRLogin: true},
	{ID: "qq", Name: "QQ 音乐", Search: true, Playlist: true, Album: true, TopList: true, Category: true, Recommend: true, UserPlaylist: true, QRLogin: true, Note: "支持 QQ / 微信扫码"},
	{ID: "kugou", Name: "酷狗音乐", Search: true, Playlist: true, Album: true, TopList: true, Category: true, Recommend: true, UserPlaylist: true, QRLogin: true},
	{ID: "kuwo", Name: "酷我音乐", Search: true, Playlist: true, Album: true, TopList: true, Category: true, Recommend: true},
	{ID: "migu", Name: "咪咕音乐", Search: true, Playlist: true, Album: true, TopList: true, Category: true},
	{ID: "qianqian", Name: "千千音乐", Search: true, Playlist: true, Album: true, Category: true, Note: "歌单搜索可能为空"},
	{ID: "soda", Name: "汽水音乐", Search: true, Playlist: true, Album: true, TopList: true, Category: true, Recommend: true, UserPlaylist: true, QRLogin: false, Note: "会员整曲需 Cookie 与本机签名器"},
	{ID: "bilibili", Name: "哔哩哔哩", Search: true, Playlist: true, QRLogin: true},
	{ID: "joox", Name: "JOOX", Search: true, Playlist: true, Album: true, Category: true},
	{ID: "jamendo", Name: "Jamendo", Search: true, Playlist: true, Album: true, Note: "CC 授权音乐"},
	{ID: "fivesing", Name: "5sing", Search: true, Playlist: true},
	{ID: "apple", Name: "Apple Music", Search: true, Playlist: true, Album: true, TopList: true, Category: true, Note: "仅提供试听片段"},
	{ID: "spotify", Name: "Spotify", Search: true, Playlist: true, Album: true, TopList: true, Category: true, Recommend: true, UserPlaylist: true, Note: "未配置凭据时使用匿名接口，仅试听"},
}

func SourceInfos() []SourceInfo {
	out := make([]SourceInfo, len(sourceInfos))
	copy(out, sourceInfos)
	return out
}

func sourceInfo(id string) (SourceInfo, bool) {
	for _, s := range sourceInfos {
		if s.ID == id {
			return s, true
		}
	}
	return SourceInfo{}, false
}

var defaultSearchSources = []string{"netease", "qq", "kugou", "kuwo", "migu"}

// provider is a uniform façade over music-lib's per-platform packages.
type provider struct {
	id       string
	name     string
	cookie   string
	instance any

	search        func(string) ([]model.Song, error)
	searchAlbum   func(string) ([]model.Playlist, error)
	searchList    func(string) ([]model.Playlist, error)
	albumSongs    func(string) ([]model.Song, error)
	listSongs     func(string) ([]model.Song, error)
	downloadURL   func(*model.Song) (string, error)
	lyric         func(*model.Song) (string, error)
	topLists      func() ([]model.TopList, error)
	topListSongs  func(string) ([]model.Song, error)
	hotSongs      func(int) ([]model.Song, error)
	categories    func() ([]model.PlaylistCategory, error)
	catPlaylists  func(string, int, int) ([]model.Playlist, error)
	recommend     func() ([]model.Playlist, error)
	userPlaylists func(int, int) ([]model.Playlist, error)
}

func newProvider(id, cookie string) (*provider, error) {
	p := &provider{id: id, cookie: cookie}
	switch id {
	case "netease":
		v := netease.New(cookie)
		p.name, p.instance = "网易云音乐", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
		p.recommend, p.userPlaylists = v.GetRecommendedPlaylists, v.GetUserPlaylists
	case "qq":
		v := qq.New(cookie)
		p.name, p.instance = "QQ 音乐", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
		p.recommend, p.userPlaylists = v.GetRecommendedPlaylists, v.GetUserPlaylists
	case "kugou":
		v := kugou.New(cookie)
		p.name, p.instance = "酷狗音乐", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
		p.recommend, p.userPlaylists = v.GetRecommendedPlaylists, v.GetUserPlaylists
	case "kuwo":
		v := kuwo.New(cookie)
		p.name, p.instance = "酷我音乐", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
		p.recommend, p.userPlaylists = v.GetRecommendedPlaylists, v.GetUserPlaylists
	case "migu":
		v := migu.New(cookie)
		p.name, p.instance = "咪咕音乐", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
	case "qianqian":
		v := qianqian.New(cookie)
		p.name, p.instance = "千千音乐", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
	case "soda":
		v := soda.New(cookie)
		p.name, p.instance = "汽水音乐", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
		p.recommend, p.userPlaylists = v.GetRecommendedPlaylists, v.GetUserPlaylists
	case "bilibili":
		v := bilibili.New(cookie)
		p.name, p.instance = "哔哩哔哩", v
		p.search, p.searchList = v.Search, v.SearchPlaylist
		p.listSongs = v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
	case "joox":
		v := joox.New(cookie)
		p.name, p.instance = "JOOX", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
	case "jamendo":
		v := jamendo.New(cookie)
		p.name, p.instance = "Jamendo", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
	case "fivesing":
		v := fivesing.New(cookie)
		p.name, p.instance = "5sing", v
		p.search, p.searchList = v.Search, v.SearchPlaylist
		p.listSongs = v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
	case "apple":
		v := apple.New(cookie)
		p.name, p.instance = "Apple Music", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
	case "spotify":
		v := spotify.New(cookie)
		p.name, p.instance = "Spotify", v
		p.search, p.searchAlbum, p.searchList = v.Search, v.SearchAlbum, v.SearchPlaylist
		p.albumSongs, p.listSongs = v.GetAlbumSongs, v.GetPlaylistSongs
		p.downloadURL, p.lyric = v.GetDownloadURL, v.GetLyrics
		p.topLists, p.topListSongs, p.hotSongs = v.GetTopLists, v.GetTopListSongs, v.GetHotSongs
		p.categories, p.catPlaylists = v.GetPlaylistCategories, v.GetCategoryPlaylists
		p.recommend, p.userPlaylists = v.GetRecommendedPlaylists, v.GetUserPlaylists
	default:
		return nil, errors.New("unknown source: " + id)
	}
	return p, nil
}
