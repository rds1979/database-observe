#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "$SKILL_DIR")")")"
CREDENTIALS="$PROJECT_DIR/src/db/postgresql.json"
LOG="$SKILL_DIR/maintenance.log"

MAX_VACUUM_SECONDS=$((3 * 3600))
MAX_CONNS=5

export PGSSLMODE=disable

parse_json() {
  python3 -c "
import json, sys
with open('$CREDENTIALS') as f:
    c = json.load(f)
print(c.get('$1', ''))
"
}

HOST=$(parse_json host)
PORT=$(parse_json port)
DB=$(parse_json database)
USER=$(parse_json user)
PASS=$(parse_json password)

export PGPASSWORD="$PASS"
PSQL="psql -h $HOST -p $PORT -U $USER -d $DB -A -t"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

die() {
  log "FATAL: $*"
  exit 1
}

START_TS=$(date +%s)
elapsed() {
  echo $(($(date +%s) - START_TS))
}
time_left() {
  local left=$((MAX_VACUUM_SECONDS - $(elapsed)))
  echo "$left"
}

# ------------------------------------------------

log "=== PostgreSQL maintenance started ==="

# 1. Проверка доступности
$PSQL -c "SELECT 1;" > /dev/null 2>&1 || die "Database unreachable"
log "DB connection OK"

# 2. Pre-flight: активные соединения
ACTIVE=$($PSQL -c "
  SELECT count(*) FROM pg_stat_activity
  WHERE state = 'active' AND pid <> pg_backend_pid();
" 2>/dev/null || echo "0")
ACTIVE=${ACTIVE:-0}
log "Active connections: $ACTIVE"

SKIP_ALL_VACUUM=false
if [ "$ACTIVE" -gt "$MAX_CONNS" ]; then
  SKIP_ALL_VACUUM=true
  log "SKIP_ALL_VACUUM: active conns ($ACTIVE) > $MAX_CONNS — running ANALYZE only"
fi

# 3. Список пользовательских таблиц
TABLES=$($PSQL -c "
  SELECT schemaname || '.' || tablename
  FROM pg_catalog.pg_tables
  WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  ORDER BY schemaname, tablename;
" 2>/dev/null || true)

if [ -z "$TABLES" ]; then
  log "No user tables found — nothing to do"
  log "=== Maintenance finished ==="
  exit 0
fi

# 4. Обход таблиц
TABLE_COUNT=$(echo "$TABLES" | wc -l)
TABLE_N=0
OK=0
SKIPPED_CONN=0
SKIPPED_TIME=0
FAILED=0

for TABLE in $TABLES; do
  TABLE_N=$((TABLE_N + 1))
  log "[$TABLE_N/$TABLE_COUNT] Processing $TABLE"

  SHORT_TABLE=$(echo "$TABLE" | sed 's/.*\.//')

  # Проверка соединений к этой таблице
  CONN_COUNT=$($PSQL -c "
    SELECT count(*) FROM pg_stat_activity
    WHERE state = 'active'
      AND pid <> pg_backend_pid()
      AND query ILIKE '%$SHORT_TABLE%';
  " 2>/dev/null || echo "0")
  CONN_COUNT=${CONN_COUNT:-0}

  if [ "$CONN_COUNT" -gt 0 ]; then
    SKIPPED_CONN=$((SKIPPED_CONN + 1))
    log "  SKIP VACUUM: $CONN_COUNT active connection(s) to $SHORT_TABLE — ANALYZE only"
  elif [ "$SKIP_ALL_VACUUM" = true ]; then
    SKIPPED_CONN=$((SKIPPED_CONN + 1))
    log "  SKIP VACUUM: pre-flight gate (active conns > $MAX_CONNS) — ANALYZE only"
  else
    # Проверка таймаута
    TL=$(time_left)
    if [ "$TL" -le 0 ]; then
      SKIPPED_TIME=$((SKIPPED_TIME + 1))
      log "  SKIP VACUUM: time budget exhausted ($((MAX_VACUUM_SECONDS / 60))m) — ANALYZE only"
    else
      log "  VACUUM FULL $TABLE (time left: ${TL}s)..."
      if $PSQL -c "VACUUM FULL VERBOSE $TABLE;" >> "$LOG" 2>&1; then
        log "  VACUUM FULL $TABLE OK"
        OK=$((OK + 1))
      else
        log "  VACUUM FULL $TABLE FAILED — continuing with ANALYZE"
        FAILED=$((FAILED + 1))
      fi
    fi
  fi

  # ANALYZE всегда
  log "  ANALYZE $TABLE..."
  if $PSQL -c "ANALYZE $TABLE;" >> "$LOG" 2>&1; then
    log "  ANALYZE $TABLE OK"
  else
    log "  ANALYZE $TABLE FAILED"
  fi
done

ELAPSED=$(elapsed)
log "=== Maintenance finished ==="
log "Total time: ${ELAPSED}s | Tables: $TABLE_COUNT | Vacuumed: $OK | Skipped(conn): $SKIPPED_CONN | Skipped(time): $SKIPPED_TIME | Failed: $FAILED"
