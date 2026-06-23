#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$(dirname "$(dirname "$SKILL_DIR")")")"
CREDENTIALS="$PROJECT_DIR/src/db/postgresql.json"
LOG="$SKILL_DIR/index-maintenance.log"

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
PSQL="psql -h $HOST -p $PORT -U $USER -d $DB"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

die() {
  log "FATAL: $*"
  exit 1
}

warn() { log "WARN: $*"; }
alert() { log "ALERT: $*"; }
info() { log "INFO: $*"; }

# ------------------------------------------------

info "=== Index maintenance started ==="

$PSQL -c "SELECT 1;" > /dev/null 2>&1 || die "Database unreachable"
info "DB connection OK"

# 1. Invalid indexes
info "--- Check 1: Invalid indexes ---"
INVALID=$($PSQL -A -t -c "
  SELECT count(*) FROM pg_catalog.pg_indexes i
  JOIN pg_catalog.pg_class c ON c.relname = i.indexname
  JOIN pg_catalog.pg_index idx ON idx.indexrelid = c.oid
  WHERE idx.indisvalid = false;
" 2>/dev/null || echo "0")
INVALID=${INVALID:-0}

if [ "$INVALID" -gt 0 ]; then
  alert "Found $INVALID invalid index(es):"
  $PSQL -c "
    SELECT schemaname, tablename, indexname
    FROM pg_catalog.pg_indexes i
    JOIN pg_catalog.pg_class c ON c.relname = i.indexname
    JOIN pg_catalog.pg_index idx ON idx.indexrelid = c.oid
    WHERE idx.indisvalid = false;
  " 2>&1 | tee -a "$LOG"
else
  info "No invalid indexes found"
fi

# 2. Unused indexes
info "--- Check 2: Unused indexes (idx_scan=0) ---"
UNUSED=$($PSQL -A -t -c "
  SELECT count(*) FROM pg_catalog.pg_stat_user_indexes
  WHERE idx_scan = 0
    AND indexrelid NOT IN (
      SELECT indexrelid FROM pg_catalog.pg_index WHERE indisprimary
    );
" 2>/dev/null || echo "0")
UNUSED=${UNUSED:-0}

if [ "$UNUSED" -gt 0 ]; then
  warn "Found $UNUSED unused index(es) — candidates for DROP INDEX CONCURRENTLY:"
  $PSQL -c "
    SELECT schemaname, relname AS tablename, indexrelname AS indexname, idx_scan
    FROM pg_catalog.pg_stat_user_indexes
    WHERE idx_scan = 0
      AND indexrelid NOT IN (
        SELECT indexrelid FROM pg_catalog.pg_index WHERE indisprimary
      );
  " 2>&1 | tee -a "$LOG"
else
  info "No unused indexes found"
fi

# 3. Dead tuple bloat & seq scans
info "--- Check 3: Dead tuple bloat & seq scans ---"
$PSQL -c "
  SELECT schemaname, relname AS tablename,
         n_live_tup, n_dead_tup,
         ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
         seq_scan, seq_tup_read,
         last_vacuum, last_autovacuum,
         last_analyze, last_autoanalyze
  FROM pg_catalog.pg_stat_user_tables
  ORDER BY dead_pct DESC NULLS LAST;
" 2>&1 | tee -a "$LOG"

DEAD_HIGH=$($PSQL -A -t -c "
  SELECT count(*) FROM pg_catalog.pg_stat_user_tables
  WHERE ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) > 20;
" 2>/dev/null || echo "0")
DEAD_HIGH=${DEAD_HIGH:-0}
if [ "$DEAD_HIGH" -gt 0 ]; then
  warn "$DEAD_HIGH table(s) with dead_pct > 20 — vacuum overdue"
fi

SEQ_HIGH=$($PSQL -A -t -c "
  SELECT count(*) FROM pg_catalog.pg_stat_user_tables
  WHERE seq_scan > 1000 AND seq_tup_read > 100000;
" 2>/dev/null || echo "0")
SEQ_HIGH=${SEQ_HIGH:-0}
if [ "$SEQ_HIGH" -gt 0 ]; then
  warn "$SEQ_HIGH table(s) with excessive seq scans — possible missing index"
fi

# 4. Checkpoint & buffer efficiency
info "--- Check 4: Checkpoint & buffer efficiency ---"
$PSQL -c "
  SELECT
    checkpoints_timed, checkpoints_req,
    ROUND(100.0 * checkpoints_timed / NULLIF(checkpoints_timed + checkpoints_req, 0), 1) AS timed_pct,
    checkpoint_write_time, checkpoint_sync_time,
    buffers_checkpoint, buffers_clean, buffers_backend,
    blks_read, blks_hit,
    ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 1) AS cache_hit_ratio
  FROM pg_catalog.pg_stat_bgwriter,
       pg_catalog.pg_stat_database WHERE datname = current_database();
" 2>&1 | tee -a "$LOG"

TIMED_PCT=$($PSQL -A -t -c "
  SELECT ROUND(100.0 * checkpoints_timed / NULLIF(checkpoints_timed + checkpoints_req, 0), 1)
  FROM pg_catalog.pg_stat_bgwriter;
" 2>/dev/null || echo "100")
TIMED_PCT=${TIMED_PCT:-100}
if (( $(echo "$TIMED_PCT < 70" | bc -l 2>/dev/null || echo 0) )); then
  alert "Checkpoint timed_pct=$TIMED_PCT% < 70% — consider increasing max_wal_size"
fi

CACHE_HIT=$($PSQL -A -t -c "
  SELECT ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 1)
  FROM pg_catalog.pg_stat_database WHERE datname = current_database();
" 2>/dev/null || echo "100")
CACHE_HIT=${CACHE_HIT:-100}
if (( $(echo "$CACHE_HIT < 95" | bc -l 2>/dev/null || echo 0) )); then
  alert "Cache hit ratio=$CACHE_HIT% < 95% — consider increasing shared_buffers"
fi

BACKEND_WRITES=$($PSQL -A -t -c "
  SELECT CASE WHEN buffers_backend > buffers_checkpoint THEN 'ALERT' ELSE 'OK' END
  FROM pg_catalog.pg_stat_bgwriter;
" 2>/dev/null || echo "OK")
if [ "$BACKEND_WRITES" = "ALERT" ]; then
  alert "buffers_backend > buffers_checkpoint — too much direct backend writing"
fi

info "=== Index maintenance finished ==="
