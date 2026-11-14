// Package mobile exposes the music core to Android (gomobile AAR) and iOS
// (gomobile XCFramework). Flutter starts the embedded HTTP server and talks to
// it over 127.0.0.1, which keeps one API implementation for every platform.
package mobile

import (
	"errors"
	"net"
	"sync"

	"github.com/interset/music-app/backend/internal/api"
)

var (
	mu       sync.Mutex
	service  *api.Service
	listener net.Listener
)

// Start boots the embedded music core. It returns the loopback port the
// Flutter side should connect to. Call Stop before starting again.
func Start(dataDir, token string) (int, error) {
	mu.Lock()
	defer mu.Unlock()
	if listener != nil {
		return listener.Addr().(*net.TCPAddr).Port, nil
	}
	if dataDir == "" {
		return 0, errors.New("dataDir is required")
	}
	if token == "" {
		return 0, errors.New("token is required")
	}
	svc, err := api.NewService(dataDir, token)
	if err != nil {
		return 0, err
	}
	ln, err := svc.Start("127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	service, listener = svc, ln
	return svc.Port(ln), nil
}

// Stop shuts the embedded server down.
func Stop() error {
	mu.Lock()
	defer mu.Unlock()
	if listener != nil {
		err := listener.Close()
		listener = nil
		service = nil
		return err
	}
	return nil
}

// Version returns the core version string.
func Version() string { return api.Version }
