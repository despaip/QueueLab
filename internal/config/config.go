package config

import "os"

type Config struct {
	Addr string
}

// Must собирает конфиг из окружения. Порт по умолчанию — :8080.
func Must() Config {
	addr := os.Getenv("HTTP_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	return Config{Addr: addr}
}
