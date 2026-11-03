package handler

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func newRouter() http.Handler {
	gin.SetMode(gin.TestMode)
	gin.DefaultWriter = io.Discard // без логов запросов в выводе тестов
	return New().Router()
}

func do(t *testing.T, r http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, reader)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// Статусы и коды ошибок — по таблице ручек из docs/TZ.md.
func TestContract(t *testing.T) {
	r := newRouter()

	validEvent := `{"group_id":1,"title":"Сдача ЛР 4–5","room":"ауд. 305",
		"starts_at":"2026-11-24T10:00:00+03:00","ends_at":"2026-11-24T13:00:00+03:00"}`

	tests := []struct {
		name, method, path, body string
		status                   int
		errCode                  string // пусто — ждём успешный ответ
	}{
		{"health", "GET", "/health", "", 200, ""},

		{"список событий", "GET", "/events", "", 200, ""},
		{"одно событие", "GET", "/events/1", "", 200, ""},
		{"событие не найдено", "GET", "/events/42", "", 404, "not_found"},
		{"id не число", "GET", "/events/abc", "", 400, "invalid_id"},
		{"id ноль", "GET", "/events/0", "", 400, "invalid_id"},

		{"создать событие", "POST", "/events", validEvent, 201, ""},
		{"пустое тело", "POST", "/events", "", 400, "invalid_json"},
		{"не JSON", "POST", "/events", "title=x", 400, "invalid_json"},
		{"поле не того типа", "POST", "/events", `{"group_id":"один"}`, 400, "invalid_json"},
		{"пустой title", "POST", "/events", strings.Replace(validEvent, "Сдача ЛР 4–5", "  ", 1), 400, "validation_error"},
		{"нет group_id", "POST", "/events", strings.Replace(validEvent, `"group_id":1,`, "", 1), 400, "validation_error"},
		{"кривая дата", "POST", "/events", strings.Replace(validEvent, "2026-11-24T10:00:00+03:00", "24.11.2026", 1), 400, "validation_error"},
		{"конец раньше начала", "POST", "/events", strings.Replace(validEvent, "T13:00", "T09:00", 1), 400, "validation_error"},

		{"очередь", "GET", "/events/1/queue", "", 200, ""},
		{"очередь чужого события", "GET", "/events/42/queue", "", 404, "not_found"},

		{"встать в очередь", "POST", "/events/1/queue", `{"student_id":21,"lab":"ЛР 3"}`, 201, ""},
		{"без lab", "POST", "/events/1/queue", `{"student_id":21}`, 400, "validation_error"},
		{"без student_id", "POST", "/events/1/queue", `{"lab":"ЛР 3"}`, 400, "validation_error"},
		{"в очередь несуществующего события", "POST", "/events/42/queue", `{"student_id":21,"lab":"ЛР 3"}`, 404, "not_found"},

		{"вызвать студента", "POST", "/events/1/queue/102/status", `{"status":"called"}`, 200, ""},
		{"неизвестный статус", "POST", "/events/1/queue/102/status", `{"status":"lost"}`, 400, "validation_error"},
		{"запись не найдена", "POST", "/events/1/queue/999/status", `{"status":"done"}`, 404, "not_found"},
		{"запись из другого события", "POST", "/events/2/queue/102/status", `{"status":"done"}`, 404, "not_found"},
		{"entry_id не число", "POST", "/events/1/queue/x/status", `{"status":"done"}`, 400, "invalid_id"},

		{"неверный метод", "DELETE", "/events/1", "", 405, "method_not_allowed"},
		{"PUT не используем", "PUT", "/events", validEvent, 405, "method_not_allowed"},
		{"неизвестный путь", "GET", "/nope", "", 404, "not_found"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := do(t, r, tt.method, tt.path, tt.body)

			if w.Code != tt.status {
				t.Fatalf("статус %d, ждали %d; тело: %s", w.Code, tt.status, w.Body)
			}
			if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
				t.Fatalf("Content-Type %q, ждали JSON", ct)
			}
			if tt.errCode == "" {
				return
			}
			var e errorResponse
			if err := json.Unmarshal(w.Body.Bytes(), &e); err != nil {
				t.Fatalf("ошибка не в формате {error, message}: %v; тело: %s", err, w.Body)
			}
			if e.Error != tt.errCode || e.Message == "" {
				t.Fatalf("ошибка %+v, ждали код %q и непустой message", e, tt.errCode)
			}
		})
	}
}

func TestCreateEventResponse(t *testing.T) {
	w := do(t, newRouter(), "POST", "/events", `{"group_id":1,"title":"  Сдача ЛР 4–5 ","room":"ауд. 305",
		"starts_at":"2026-11-24T10:00:00+03:00","ends_at":"2026-11-24T13:00:00+03:00","autocheck_required":true}`)

	var e Event
	if err := json.Unmarshal(w.Body.Bytes(), &e); err != nil {
		t.Fatal(err)
	}
	if e.ID == 0 || e.Status != "scheduled" || e.Title != "Сдача ЛР 4–5" || !e.AutocheckRequired {
		t.Fatalf("неожиданное событие: %+v", e)
	}
}

func TestQueueResponses(t *testing.T) {
	r := newRouter()

	t.Run("пустая очередь — [], а не null", func(t *testing.T) {
		w := do(t, r, "GET", "/events/2/queue", "")
		if got := strings.TrimSpace(w.Body.String()); got != "[]" {
			t.Fatalf("тело %q, ждали []", got)
		}
	})

	t.Run("новая запись встаёт в конец", func(t *testing.T) {
		w := do(t, r, "POST", "/events/1/queue", `{"student_id":21,"lab":" ЛР 3 ","teacher_only":true}`)
		var q QueueEntry
		if err := json.Unmarshal(w.Body.Bytes(), &q); err != nil {
			t.Fatal(err)
		}
		if q.EventID != 1 || q.Status != "waiting" || q.Lab != "ЛР 3" || !q.TeacherOnly ||
			q.Position != len(mockQueues[1])+1 || q.ETAMinutes <= 0 {
			t.Fatalf("неожиданная запись: %+v", q)
		}
	})

	t.Run("принятая запись выходит из очереди", func(t *testing.T) {
		w := do(t, r, "POST", "/events/1/queue/102/status", `{"status":"done"}`)
		var q QueueEntry
		if err := json.Unmarshal(w.Body.Bytes(), &q); err != nil {
			t.Fatal(err)
		}
		if q.ID != 102 || q.Status != "done" || q.Position != 0 {
			t.Fatalf("неожиданная запись: %+v", q)
		}
	})

	t.Run("мок не меняется от запросов", func(t *testing.T) {
		if mockQueues[1][1].Status != "waiting" {
			t.Fatalf("POST изменил зашитые данные: %+v", mockQueues[1][1])
		}
	})
}
