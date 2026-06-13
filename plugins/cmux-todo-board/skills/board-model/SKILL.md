---
name: board-model
description: Manage project-level model assignments via profiles (select, list, catalog).
---

# board-model

Manage model assignments stored in `.tasks/config.json`. Models are assigned
to roles (profiles) via `select --role`. The `catalog` command ingests the live
`pi --list-models` catalog for model discovery. `list` shows current profile
assignments with free/paid annotations.

## Commands

```
board-model catalog [--refresh] [--json]
```
Ingest the live `pi --list-models` catalog and cache to `.tasks/model-catalog.json`.
- `--refresh` — Re-run pi even if cache exists.
- `--json` — Print the cached catalog as JSON array.
Default prints a readable table grouped by provider with FREE/paid column.

```
board-model select --role <role> --id <provider/model> [--allow-paid] [--allow-claude]
```
Assign a catalog model to a role, persisted in `.tasks/config.json` under
`.profiles.<role>`.
- `--role` — Target role: `backend`, `backend-fast`, `repo-scout`, `docs`,
  `test`, `tiny-patch`, `review`, `frontend`, `frontend-top`.
- `--id` — Catalog model id in `provider/model` format.
- `--allow-paid` — Allow assigning a paid model to a role whose default is free
  (`backend-fast`, `repo-scout`, `docs`, `test`).
- `--allow-claude` — Allow assigning an anthropic model to a frontend role.

```
board-model list
```
List current profile assignments with `(free)` / `(paid)` annotations from the
catalog. Emits a WARNING when paid model assignments are detected.

## Validation rules

- **Role**: Must be one of the valid profiles.
- **Model id**: Must be in `provider/model` format and exist in the catalog.
- **Free guard**: Roles with free defaults block paid models unless `--allow-paid`.
- **Claude guard**: Frontend roles block anthropic models unless `--allow-claude`.

## Resolution

Profile assignments are resolved at dispatch time via
`board-config --get-profile <name>`. See `board-config` skill for details.

## Examples

```bash
# Assign a free model to the docs role
board-model select --role docs --id opencode/deepseek-v4-flash-free

# Assign a paid model with explicit permission
board-model select --role docs --id opencode-go/deepseek-v4-pro --allow-paid

# Review current assignments
board-model list

# Refresh and browse the model catalog
board-model catalog --refresh
```
