# database-observe

Мониторинг и обслуживание баз данных PostgreSQL и ClickHouse.

## Используемые технологии

- **PostgreSQL** — БД `grace`
- **ClickHouse** — БД `moex` (данные MOEX, пользовательские события)

## Доступные MCP-серверы

| Сервер    | Описание                                                |
|-----------|---------------------------------------------------------|
| clickhouse| Доступ к ClickHouse через Altinity MCP                  |
| github    | Доступ к GitHub API (пользователь rds1979)              |

## Документация

- `AGENTS.md` — правила и инструкции для OpenCode
- `.opencode/skills/postgres-maintenance/SKILL.md` — ежедневное обслуживание PostgreSQL
- `.opencode/skills/index-maintenance/SKILL.md` — мониторинг индексов PostgreSQL
