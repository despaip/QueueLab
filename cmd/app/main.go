package main

import (
	"log"

	"queuelab/internal/config"
	"queuelab/internal/handler"
)

func main() {
	cfg := config.Must()
	h := handler.New()

	log.Printf("QueueLab слушает %s", cfg.Addr)
	if err := h.Run(cfg.Addr); err != nil {
		log.Fatal(err)
	}
}
