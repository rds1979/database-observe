---
name: index-maintenance
description: Use for PostgreSQL index health checks and maintenance. Runs every 3 hours: scans for invalid/unused indexes, dead tuple bloat, seq scans, vacuum/analyze staleness, and checkpoint/buffer efficiency in the database from src/db/postgresql.json.
---

# Index maintenance

## Connection

- DB credentials: `src/db/postgresql.json`
- Connect via `psql` with `PGPASSWORD`.
- Use `PGSSLMODE=disable` unless the config says otherwise.

## Checks (run all, every 3 hours)

### 1. Invalid indexes

```sql
SELECT schemaname, tablename, indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE indexname IN (
  SELECT indexname::text FROM pg_catalog.pg_indexes
  EXCEPT
  SELECT relname::text FROM pg_catalog.pg_class WHERE relkind = 'i'
);
```

Alternatively, check `pg_index.indisvalid`:

```sql
SELECT schemaname, tablename, indexname
FROM pg_catalog.pg_indexes i
JOIN pg_catalog.pg_class c ON c.relname = i.indexname
JOIN pg_catalog.pg_index idx ON idx.indexrelid = c.oid
WHERE idx.indisvalid = false;
```

If any found: `REINDEX INDEX CONCURRENTLY <name>` (or `REINDEX TABLE CONCURRENTLY` for many).

### 2. Unused indexes

```sql
SELECT schemaname, relname AS tablename, indexrelname AS indexname, idx_scan
FROM pg_catalog.pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelid NOT IN (
    SELECT indexrelid FROM pg_catalog.pg_index WHERE indisprimary
  );
```

Log candidates for `DROP INDEX CONCURRENTLY`. Do not drop automatically — just report.

### 3. Dead tuple bloat & seq scans

```sql
SELECT schemaname, relname AS tablename,
       n_live_tup, n_dead_tup,
       ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       seq_scan, seq_tup_read,
       last_vacuum, last_autovacuum,
       last_analyze, last_autoanalyze
FROM pg_catalog.pg_stat_user_tables
ORDER BY dead_pct DESC NULLS LAST;
```

Alert if:
- `dead_pct > 20` — stale stats, vacuum overdue
- `seq_scan > 1000 AND seq_tup_read > 100000` — may be missing an index
- `last_vacuum` / `last_analyze` more than 24h ago on high-churn tables

### 4. Checkpoint & buffer efficiency

```sql
SELECT
  checkpoints_timed, checkpoints_req,
  ROUND(100.0 * checkpoints_timed / NULLIF(checkpoints_timed + checkpoints_req, 0), 1) AS timed_pct,
  checkpoint_write_time, checkpoint_sync_time,
  buffers_checkpoint, buffers_clean, buffers_backend,
  blks_read, blks_hit,
  ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 1) AS cache_hit_ratio
FROM pg_catalog.pg_stat_bgwriter,
     pg_catalog.pg_stat_database WHERE datname = current_database();
```

Alert if:
- `timed_pct < 70` — too many request-based checkpoints (increase `max_wal_size`)
- `cache_hit_ratio < 95` — low buffer cache hit ratio (consider increasing `shared_buffers`)
- `buffers_backend > buffers_checkpoint` — too much direct backend writing

## Reporting

- Log all findings with severity: INFO / WARN / ALERT.
- Never drop or modify indexes automatically — list candidates and report.

## Scheduling

- Expected run: **every 3 hours**.
- This skill defines **what** to do. The actual scheduling is outside the skill scope.
