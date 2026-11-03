# --- 1. Сборка: Go и зависимости нужны только здесь ---
FROM golang:1.26-alpine AS build

WORKDIR /src

# Сначала только go.mod и go.sum: слой с зависимостями кэшируется
# и не перекачивается, пока они не меняются.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO_ENABLED=0 — статический бинарник, запустится в любом Linux-образе.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/app

# --- 2. Запуск: маленький образ, в нём только бинарник ---
FROM alpine:3.24

# curl — чтобы проверять сервис изнутри контейнера и для HEALTHCHECK.
RUN apk add --no-cache curl

WORKDIR /app
COPY --from=build /out/server ./server

ENV GIN_MODE=release \
    HTTP_ADDR=:8080
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=2s --start-period=3s --retries=3 \
    CMD curl -fsS http://localhost:8080/health || exit 1

USER nobody
CMD ["./server"]
