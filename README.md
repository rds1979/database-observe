# database-observe

Мониторинг и обслуживание баз данных PostgreSQL (`grace`) и ClickHouse (`moex`).

## Подключённые базы

| База       | Хост             | Порт  | Назначение            |
|------------|------------------|-------|-----------------------|
| PostgreSQL | 10.92.94.35:5432 | 5432  | БД `grace`            |
| ClickHouse | 10.92.94.41      | 8123  | БД `moex` (облигации) |

## Доступные MCP-серверы

| Сервер    | Описание                                                |
|-----------|---------------------------------------------------------|
| clickhouse| Доступ к ClickHouse `moex` через Altinity MCP           |
| github    | Доступ к GitHub API (пользователь rds1979)              |

## Таблицы ClickHouse

- **bonds** — данные по облигациям (ОФЗ и др.)
- **user_events** — события пользователей (клики, сессии)

## Документация

- `AGENTS.md` — правила и инструкции для OpenCode
- `.opencode/skills/postgres-maintenance/SKILL.md` — ежедневное обслуживание PostgreSQL
- `.opencode/skills/index-maintenance/SKILL.md` — мониторинг индексов PostgreSQL
