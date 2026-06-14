---
name: board-config
description: Manage board runtime configuration (language, profile resolution) stored in .tasks/config.json.
---

# board-config

Manage the board's runtime configuration, stored in `.tasks/config.json`.

## Commands

```
board-config --get
```
Print the current configured language. Defaults to **EN** if no config file
or `language` key is set.

```
board-config --set-language <code>
```
Write or update the language code in `.tasks/config.json`, preserving any
other keys already in the file. The code is normalized (uppercased, trimmed).
Rejects empty or whitespace-only input.

```
board-config --get-profile <name> [--provider] [--model] [--thinking] [--tools] [--json]
```
Resolve a Pi role profile. Reads overrides from `.profiles.<name>` in
`.tasks/config.json`, falls back to built-in defaults.

- `--provider` — print the provider field only.
- `--model` — print the model field only (default if no selector).
- `--thinking` — print the thinking field only.
- `--tools` — print the tools field only.
- `--json` — print full resolution as `{provider, model, thinking, tools}`.

Valid profiles: `backend`, `backend-fast`, `repo-scout`, `docs`, `test`,
`tiny-patch`, `review`, `frontend`, `frontend-top`.

## Profile resolution

`--get-profile` resolves a profile by merging built-in defaults with per-field
overrides from `.profiles.<name>` in `.tasks/config.json`. Each field
(`provider`, `model`, `thinking`, `tools`) can be independently overridden.

Profiles are the single source of truth for model configuration. They carry
the full Pi launch contract (provider, model, thinking level, tool set) and
are consumed by `agent-spawn.sh --profile <name>` at dispatch time.

## Default language rule

The board's default working language is **English (EN)**. All generated text
(GitHub issue titles/bodies, documentation) is produced in EN unless the user
explicitly overrides it with `board-config --set-language <code>`.

## See also

