# AGENTS.md

This repository is **empty**. It was created to hold a `database-observe` project but has no files yet (no README, no manifests, no source code).

Once the project is initialized (e.g., `npm init`, `cargo init`, or whatever tooling is chosen), update this file by re-running the AGENTS.md generation workflow.

## Project assets

- DB credentials: `src/db/postgresql.json` — PostgreSQL `grace` db, user `biview`, host `10.92.94.35:5432`
- Maintenance skill: `.opencode/skills/postgres-maintenance/SKILL.md` — daily VACUUM FULL + ANALYZE with connection-gate rules and 3h timeout
- Index maintenance skill: `.opencode/skills/index-maintenance/SKILL.md` — every 3h: invalid/unused indexes, dead tuple bloat, seq scans, vacuum/analyze staleness, checkpoint & buffer efficiency

Expected future content to capture here:
- Build, test, lint, typecheck commands
- Monorepo structure (if any)
- Framework and toolchain specifics
- CI and deployment workflow
- Any non-obvious conventions

## OpenCode learning plan

**Level 1 — Пользователь**: что такое OC, установка, базовые команды, инструменты, первый `opencode.json`.
**Level 2 — Настройщик**: `opencode.json` глубоко, permissions, references, agents, skills, instructions (AGENTS.md), MCP, shell/env.
**Level 3 — Интегратор**: plugins (архитектура, хуки), multi-agent, compaction, snapshot, providers, share/autoupdate, escape hatches.
**Level 4 — Эксперт**: архитектура OC из исходников, сложные плагины (auth, provider, tool definition), contributing, security model.

Level 1 — пройдено.
Level 2 — на паузе. Продолжить: opencode.json глубоко, permissions, references, agents, MCP, shell/env.
