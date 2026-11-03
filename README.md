# QueueLab

Электронная очередь на сдачу лабораторных: события приёма, позиция и прогноз ожидания,
статусы «вызван / принят / не пришёл».

Сейчас (занятие 03) это каркас API на Gin с моками: ручки и контракт есть,
данных и бизнес-логики ещё нет. ТЗ лежит в [docs/TZ.md](docs/TZ.md).

## Структура

```
cmd/app/main.go              точка входа: конфиг → handler.Run
internal/config/config.go    HTTP_ADDR из окружения, по умолчанию :8080
internal/handler/            роуты, Run, моки — живой только этот слой
  handler.go                 Router, /health, формат ошибок
  events.go                  /events
  queue.go                   /events/{id}/queue
  handler_test.go            тесты контракта
internal/usecase/            пакет есть, кода нет
internal/storage/            пакет есть, кода нет
```

## Ручки

| Метод и путь | Что делает |
|---|---|
| `GET /health` | сервис жив |
| `GET /events` | расписание событий приёма |
| `GET /events/{id}` | одно событие или 404 |
| `POST /events` | создать событие (201) |
| `GET /events/{id}/queue` | очередь события с позициями и прогнозом |
| `POST /events/{id}/queue` | встать в очередь (201) |
| `POST /events/{id}/queue/{entry_id}/status` | `called` / `done` / `no_show` / `left` |

Ошибки всегда в одном формате: `{"error": "not_found", "message": "событие 42 не найдено"}`.

## Запуск локально

```bash
go mod download
go test ./...
go run ./cmd/app                    # слушает :8080
HTTP_ADDR=:9090 go run ./cmd/app    # другой порт
```

```bash
curl localhost:8080/health
curl localhost:8080/events/1
curl -X POST localhost:8080/events/1/queue \
  -H 'Content-Type: application/json' \
  -d '{"student_id": 21, "lab": "ЛР 3"}'
```

## Docker

```bash
docker build -t queuelab:0.1 .
docker run -d --name queuelab -p 8080:8080 queuelab:0.1

docker ps                                   # STATUS станет (healthy)
curl localhost:8080/events                  # с хоста
docker exec queuelab curl -s localhost:8080/events   # изнутри контейнера
docker logs queuelab
docker stop queuelab && docker rm queuelab
```

Проверка из ДЗ одной командой: соберёт образ, поднимет контейнер и сверит
ответы с хоста и изнутри по всем ручкам.

```bash
scripts/smoke.sh
```

Выложить образ в реестр:

```bash
docker login
docker tag queuelab:0.1 <user>/queuelab:0.1
docker push <user>/queuelab:0.1
# у другого человека:
docker run -p 8080:8080 <user>/queuelab:0.1
```
