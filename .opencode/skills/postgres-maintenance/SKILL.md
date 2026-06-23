---
name: postgres-maintenance
description: Use ONLY for scheduled PostgreSQL maintenance. Runs daily at 00:15: VACUUM FULL + ANALYZE on all tables in the database specified in src/db/postgresql.json with connection-gate checks and a 3-hour timeout.
---

# PostgreSQL maintenance

## Connection

- DB credentials: `src/db/postgresql.json`
- Connect via `psql` with `PGPASSWORD`.
- Use `PGSSLMODE=disable` unless the config says otherwise.

## Pre-flight

1. Check total active connections:
   ```sql
   SELECT count(*) FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid();
   ```
2. If `count > 5`, skip **all** VACUUM FULL operations — run ANALYZE only (on all tables).
3. Time limit for all VACUUM FULL operations combined: **3 hours**. Track elapsed time in shell. If time runs out, skip remaining VACUUM FULL and run ANALYZE on the tables that were vacuumed plus any remaining tables.

## Per-table procedure

For every user table in `pg_catalog` (excluding system schemas):

1. Fetch current connections touching this table:
   ```sql
   SELECT count(*) FROM pg_stat_activity
   WHERE state = 'active'
     AND pid <> pg_backend_pid()
     AND query ILIKE '%<table_name>%';
   ```
2. If `count > 0`, skip VACUUM FULL for this table (run ANALYZE only).
3. Otherwise run:
   ```sql
   VACUUM FULL VERBOSE <schema>.<table>;
   ```
4. After VACUUM FULL (or if it was skipped), run:
   ```sql
   ANALYZE <schema>.<table>;
   ```

## Scheduling

- Expected run: **daily at 00:15**.
- This skill defines **what** to do. The actual scheduling (cron, systemd timer, etc.) is outside this skill's scope.

## Error handling

- If the DB is unreachable, log the failure and abort — do not retry.
- If a single table's VACUUM FULL fails, log the error and continue with the next table.
- Log all skipped tables with the reason (active connections / time budget exceeded).
