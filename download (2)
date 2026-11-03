// Package handler — HTTP-слой QueueLab: роуты, разбор запросов, ответы.
//
// На занятии 03 живой только этот слой: ответы — моки прямо отсюда,
// до usecase и storage запрос не доходит.
package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type Handler struct{}

func New() *Handler {
	return &Handler{}
}

// Run поднимает HTTP-сервер и блокируется, пока он работает.
func (h *Handler) Run(addr string) error {
	return h.Router().Run(addr)
}

// Router собирает все роуты. Отдельно от Run — чтобы тесты
// могли гонять запросы без запуска сервера.
func (h *Handler) Router() *gin.Engine {
	r := gin.Default()
	_ = r.SetTrustedProxies(nil) // за прокси пока не стоим

	// Неверный метод — 405, а не 404, и тоже в нашем формате ошибок.
	r.HandleMethodNotAllowed = true
	r.NoMethod(func(c *gin.Context) {
		writeError(c, http.StatusMethodNotAllowed, "method_not_allowed", "метод не поддерживается для этого пути")
	})
	r.NoRoute(func(c *gin.Context) {
		writeError(c, http.StatusNotFound, "not_found", "такого пути нет")
	})

	r.GET("/health", h.Health)

	r.GET("/events", h.ListEvents)
	r.POST("/events", h.CreateEvent)
	r.GET("/events/:id", h.GetEvent)

	r.GET("/events/:id/queue", h.ListQueue)
	r.POST("/events/:id/queue", h.JoinQueue)
	r.POST("/events/:id/queue/:entry_id/status", h.SetEntryStatus)

	return r
}

func (h *Handler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// errorResponse — единый формат ошибки из ТЗ.
type errorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func writeError(c *gin.Context, status int, code, message string) {
	c.AbortWithStatusJSON(status, errorResponse{Error: code, Message: message})
}

// pathID читает положительный целый параметр пути. Если он кривой,
// сам пишет 400 и возвращает ok == false.
func pathID(c *gin.Context, name string) (int, bool) {
	id, err := strconv.Atoi(c.Param(name))
	if err != nil || id <= 0 {
		writeError(c, http.StatusBadRequest, "invalid_id", name+" должен быть положительным целым числом")
		return 0, false
	}
	return id, true
}
