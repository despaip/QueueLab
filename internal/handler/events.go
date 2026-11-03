package handler

import (
	"fmt"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
)

// Event — событие приёма. Форма ответа уже как у будущего CRUD.
type Event struct {
	ID                int       `json:"id"`
	GroupID           int       `json:"group_id"`
	Title             string    `json:"title"`
	Room              string    `json:"room"`
	StartsAt          time.Time `json:"starts_at"`
	EndsAt            time.Time `json:"ends_at"`
	Status            string    `json:"status"` // scheduled | open | closed
	AutocheckRequired bool      `json:"autocheck_required"`
}

type createEventRequest struct {
	GroupID           int    `json:"group_id"`
	Title             string `json:"title"`
	Room              string `json:"room"`
	StartsAt          string `json:"starts_at"`
	EndsAt            string `json:"ends_at"`
	AutocheckRequired bool   `json:"autocheck_required"`
}

const maxTitleLen = 200

// msk — фиксированная зона, чтобы не зависеть от tzdata в образе.
var msk = time.FixedZone("MSK", 3*60*60)

func at(day, hour, minute int) time.Time {
	return time.Date(2026, time.November, day, hour, minute, 0, 0, msk)
}

// mockEvents — зашитые события. Только читаем, поэтому mutex не нужен.
// На занятии 04 их заменит storage.
var mockEvents = []Event{
	{ID: 1, GroupID: 1, Title: "Сдача ЛР 1–3", Room: "ауд. 305",
		StartsAt: at(10, 10, 0), EndsAt: at(10, 13, 0), Status: "open", AutocheckRequired: true},
	{ID: 2, GroupID: 1, Title: "Защита курсовых работ", Room: "ауд. 412",
		StartsAt: at(17, 15, 0), EndsAt: at(17, 18, 0), Status: "scheduled", AutocheckRequired: false},
	{ID: 3, GroupID: 2, Title: "Сдача ЛР 4, повторный приём", Room: "ауд. 218",
		StartsAt: at(3, 9, 0), EndsAt: at(3, 12, 0), Status: "closed", AutocheckRequired: true},
}

func findEvent(id int) (Event, bool) {
	for _, e := range mockEvents {
		if e.ID == id {
			return e, true
		}
	}
	return Event{}, false
}

// eventFromPath читает :id и ищет событие. На любой ошибке сам пишет ответ.
func eventFromPath(c *gin.Context) (Event, bool) {
	id, ok := pathID(c, "id")
	if !ok {
		return Event{}, false
	}
	e, found := findEvent(id)
	if !found {
		writeError(c, http.StatusNotFound, "not_found", fmt.Sprintf("событие %d не найдено", id))
		return Event{}, false
	}
	return e, true
}

// GET /events
func (h *Handler) ListEvents(c *gin.Context) {
	c.JSON(http.StatusOK, mockEvents)
}

// GET /events/:id
func (h *Handler) GetEvent(c *gin.Context) {
	e, ok := eventFromPath(c)
	if !ok {
		return
	}
	c.JSON(http.StatusOK, e)
}

// POST /events — проверяем вход и отвечаем «создано». В память пока не кладём.
func (h *Handler) CreateEvent(c *gin.Context) {
	var req createEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, "invalid_json", "тело запроса должно быть JSON-объектом с полями нужных типов")
		return
	}

	e, msg := req.validate()
	if msg != "" {
		writeError(c, http.StatusBadRequest, "validation_error", msg)
		return
	}

	e.ID = len(mockEvents) + 1 // мок: настоящий id выдаст база
	e.Status = "scheduled"
	c.JSON(http.StatusCreated, e)
}

// validate проверяет запрос и собирает из него Event.
// Возвращает текст первой ошибки или пустую строку.
func (r createEventRequest) validate() (Event, string) {
	title := strings.TrimSpace(r.Title)
	room := strings.TrimSpace(r.Room)

	switch {
	case r.GroupID <= 0:
		return Event{}, "group_id должен быть положительным"
	case title == "":
		return Event{}, "title не может быть пустым"
	case utf8.RuneCountInString(title) > maxTitleLen:
		return Event{}, fmt.Sprintf("title не длиннее %d символов", maxTitleLen)
	case room == "":
		return Event{}, "room не может быть пустым"
	}

	startsAt, err := time.Parse(time.RFC3339, r.StartsAt)
	if err != nil {
		return Event{}, "starts_at: нужна дата в формате RFC 3339, например 2026-11-24T10:00:00+03:00"
	}
	endsAt, err := time.Parse(time.RFC3339, r.EndsAt)
	if err != nil {
		return Event{}, "ends_at: нужна дата в формате RFC 3339, например 2026-11-24T13:00:00+03:00"
	}
	if !endsAt.After(startsAt) {
		return Event{}, "ends_at должен быть позже starts_at"
	}

	return Event{
		GroupID:           r.GroupID,
		Title:             title,
		Room:              room,
		StartsAt:          startsAt,
		EndsAt:            endsAt,
		AutocheckRequired: r.AutocheckRequired,
	}, ""
}
