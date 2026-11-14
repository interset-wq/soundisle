package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/interset/music-app/backend/internal/api"
)

func main() {
	log.SetOutput(os.Stderr)
	var (
		addr    = flag.String("addr", "127.0.0.1:0", "listen address")
		dataDir = flag.String("data-dir", "", "application data directory")
		token   = flag.String("token", "", "API token (generated when empty)")
		asJSON  = flag.Bool("json", true, "print a single JSON line with the listening port")
	)
	flag.Parse()

	dir := *dataDir
	if dir == "" {
		dir = defaultDataDir()
	}
	if *token == "" {
		*token = os.Getenv("SOUNDISLE_TOKEN")
	}
	if *token == "" {
		*token = randomToken()
	}
	service, err := api.NewService(dir, *token)
	if err != nil {
		log.Fatalf("start service: %v", err)
	}
	listener, err := service.Start(*addr)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	port := service.Port(listener)
	baseURL := "http://" + hostForURL(listener.Addr()) + fmt.Sprintf(":%d", port)

	if *asJSON {
		payload, _ := json.Marshal(map[string]any{
			"port": port, "token": *token, "baseUrl": baseURL, "dataDir": dir,
		})
		fmt.Println(string(payload))
	} else {
		log.Printf("music core listening on %s", baseURL)
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	_ = listener.Close()
}

func defaultDataDir() string {
	if dir, err := os.UserConfigDir(); err == nil && dir != "" {
		return filepath.Join(dir, "Soundisle")
	}
	return filepath.Join(".", "data")
}

func hostForURL(addr net.Addr) string {
	if tcp, ok := addr.(*net.TCPAddr); ok {
		if tcp.IP.IsUnspecified() {
			return "127.0.0.1"
		}
		return tcp.IP.String()
	}
	return "127.0.0.1"
}

func randomToken() string {
	buf := make([]byte, 24)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}
