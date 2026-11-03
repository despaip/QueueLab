package handler

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// QueueEntry — запись студента в очереди на событие.
type QueueEntry struct {
	ID          int       `json:"id"`
	EventID     int       `json:"event_id"`
	StudentID   int       `json:"student_id"`
	StudentName string    `json:"student_name"`
	Lab         string    `json:"lab"`
	TeacherOnly bool      `json:"teacher_only"`
	Priority    int       `json:"priority"`
	Status      string    `json:"status"`      // waiting | called | done | no_show | left
	Position    int       `json:"position"`    // с 1; 0 — уже не в очереди
	ETAMinutes  int       `json:"eta_minutes"` // прогноз ожидания
	JoinedAt    time.Time `json:"joined_at"`
}

type joinQueueRequest struct {
	StudentID   int    `json:"student_id"` // после JWT придёт из токена
	Lab         string `json:"lab"`
	TeacherOnly bool   `json:"teacher_only"`
}

type setStatusRequest struct {
	Status string `json:"status"`
}

// Статусы, которые можно выставить записи через POST .../status.
var settableStatuses = map[string]bool{
	"called":  true, // проверяющий вызвал
	"done":    true, // работу приняли
	"no_show": true, // не пришёл по вызову
	"left":    true, // вышел из очереди сам
}

// mockMinutesPerStudent — грубая заглушка прогноза. Настоящий прогноз
// по истории преподавателя и типу работы будет в usecase.
const mockMinutesPerStudent = 6

// mockNow — зашитое «текущее время», чтобы моки отвечали предсказуемо.
var mockNow = at(10, 10, 20)

// mockQueues — зашитые очереди по id события. Только читаем.
var mockQueues = map[int][]QueueEntry{
	1: {
		{ID: 101, EventID: 1, StudentID: 7, StudentName: "Анна Соколова", Lab: "ЛР 2",
			Status: "called", Position: 1, ETAMinutes: 0, JoinedAt: at(10, 10, 2)},
		{ID: 102, EventID: 1, StudentID: 12, StudentName: "Илья Петров", Lab: "ЛР 1",
			Priority: 2, Status: "waiting", Position: 2, ETAMinutes: 5, JoinedAt: at(10, 10, 5)},
		{ID: 103, EventID: 1, StudentID: 15, StudentName: "Мария Кузнецова", Lab: "ЛР 3",
			TeacherOnly: true, Status: "waiting", Position: 3, ETAMinutes: 12, JoinedAt: at(10, 10, 11)},
	},
	2: {},
	3: {
		{ID: 301, EventID: 3, StudentID: 7, StudentName: "Анна Соколова", Lab: "ЛР 4",
			Status: "done", JoinedAt: at(3, 9, 4)},
		{ID: 302, EventID: 3, StudentID: 21, StudentName: "Олег Смирнов", Lab: "ЛР 4",
			Status: "no_show", JoinedAt: at(3, 9, 15)},
	},
}

// GET /events/:id/queue
func (h *Handler) ListQueue(c *gin.Context) {
	e, ok := eventFromPath(c)
	if !ok {
		return
	}
	queue := mockQueues[e.ID]
	if queue == nil {
		queue = []QueueEntry{} // пустая очередь — [], а не null
	}
	c.JSON(http.StatusOK, queue)
}

// POST /events/:id/queue — встать в очередь. Отвечаем «создано», в память не кладём.
func (h *Handler) JoinQueue(c *gin.Context) {
	e, ok := eventFromPath(c)
	if !ok {
		return
	}

	var req joinQueueRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, "invalid_json", "тело запроса должно быть JSON-объектом с полями нужных типов")
		return
	}
	lab := strings.TrimSpace(req.Lab)
	switch {
	case req.StudentID <= 0:
		writeError(c, http.StatusBadRequest, "validation_error", "student_id должен быть положительным")
		return
	case lab == "":
		writeError(c, http.StatusBadRequest, "validation_error", "lab не может быть пустым")
		return
	}

	// Мок: встаём в конец зашитой очереди. Проверка статуса события (409),
	// баллы приоритета и санкции — правила usecase, придут позже.
	position := len(mockQueues[e.ID]) + 1
	c.JSON(http.StatusCreated, QueueEntry{
		ID:          e.ID*100 + position, // мок: настоящий id выдаст база
		EventID:     e.ID,
		StudentID:   req.StudentID,
		StudentName: fmt.Sprintf("Студент %d", req.StudentID), // имя возьмём из User
		Lab:         lab,
		TeacherOnly: req.TeacherOnly,
		Status:      "waiting",
		Position:    position,
		ETAMinutes:  (position - 1) * mockMinutesPerStudent,
		JoinedAt:    mockNow,
	})
}

// POST /events/:id/queue/:entry_id/status — вызвать, принять, отметить неявку, выйти.
func (h *Handler) SetEntryStatus(c *gin.Context) {
	e, ok := eventFromPath(c)
	if !ok {
		return
	}
	entryID, ok := pathID(c, "entry_id")
	if !ok {
		return
	}
	entry, found := findEntry(e.ID, entryID)
	if !found {
		writeError(c, http.StatusNotFound, "not_found", fmt.Sprintf("запись %d в очереди события %d не найдена", entryID, e.ID))
		return
	}

	var req setStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, "invalid_json", "тело запроса должно быть JSON-объектом с полями нужных типов")
		return
	}
	if !settableStatuses[req.Status] {
		writeError(c, http.StatusBadRequest, "validation_error", "status: одно из called, done, no_show, left")
		return
	}

	// Мок: меняем копию и отдаём её. Пересчёт позиций остальных — в usecase.
	entry.Status = req.Status
	if req.Status != "called" {
		entry.Position, entry.ETAMinutes = 0, 0 // запись вышла из очереди
	}
	c.JSON(http.StatusOK, entry)
}

func findEntry(eventID, entryID int) (QueueEntry, bool) {
	for _, q := range mockQueues[eventID] {
		if q.ID == entryID {
			return q, true
		}
	}
	return QueueEntry{}, false
}
