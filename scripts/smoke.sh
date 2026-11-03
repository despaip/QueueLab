#!/usr/bin/env bash
# Поднимает QueueLab в контейнере и сверяет ответы curl с хоста и изнутри контейнера.
#
#   scripts/smoke.sh                  # собрать образ и проверить
#   SKIP_BUILD=1 scripts/smoke.sh     # проверить уже собранный образ
#   PORT=9090 scripts/smoke.sh        # если 8080 на хосте занят
set -euo pipefail

IMAGE=${IMAGE:-queuelab:0.1}
NAME=${NAME:-queuelab-smoke}
PORT=${PORT:-8080}

cd "$(dirname "$0")/.."

if [[ -z "${SKIP_BUILD:-}" ]]; then
  docker build -t "$IMAGE" .
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "$PORT:8080" "$IMAGE" >/dev/null
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 50); do
  curl -fsS "localhost:$PORT/health" >/dev/null 2>&1 && break
  sleep 0.2
done

# метод | путь | тело | ожидаемый статус
checks=(
  'GET|/health||200'
  'GET|/events||200'
  'GET|/events/1||200'
  'GET|/events/42||404'
  'GET|/events/abc||400'
  'POST|/events|{"group_id":1,"title":"Сдача ЛР 4–5","room":"ауд. 305","starts_at":"2026-11-24T10:00:00+03:00","ends_at":"2026-11-24T13:00:00+03:00"}|201'
  'POST|/events|{"group_id":1,"title":""}|400'
  'GET|/events/1/queue||200'
  'GET|/events/2/queue||200'
  'POST|/events/1/queue|{"student_id":21,"lab":"ЛР 3"}|201'
  'POST|/events/1/queue/102/status|{"status":"called"}|200'
  'POST|/events/1/queue/999/status|{"status":"done"}|404'
  'DELETE|/events/1||405'
)

request() { # request <откуда: host|container> <метод> <путь> <тело>
  local where=$1 method=$2 path=$3 body=$4
  local args=(-s -w '\n%{http_code}' -X "$method")
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi
  if [[ $where == host ]]; then
    curl "${args[@]}" "localhost:$PORT$path"
  else
    docker exec "$NAME" curl "${args[@]}" "localhost:8080$path"
  fi
}

fail=0
for check in "${checks[@]}"; do
  IFS='|' read -r method path body want <<<"$check"
  host=$(request host "$method" "$path" "$body" || true)
  inside=$(request container "$method" "$path" "$body" || true)
  got=${host##*$'\n'}

  if [[ "$host" == "$inside" && "$got" == "$want" ]]; then
    printf 'OK    %-6s %-30s %s\n' "$method" "$path" "$got"
  else
    printf 'FAIL  %-6s %-30s хост %s, ждали %s\n' "$method" "$path" "$got" "$want"
    [[ "$host" != "$inside" ]] && printf '      хост:      %s\n      контейнер: %s\n' "${host//$'\n'/ }" "${inside//$'\n'/ }"
    fail=1
  fi
done

echo
docker ps --filter "name=$NAME" --format 'контейнер {{.Names}}: {{.Status}}'
if (( fail )); then
  echo "Есть расхождения."
  exit 1
fi
echo "Ответы с хоста и из контейнера совпадают."
