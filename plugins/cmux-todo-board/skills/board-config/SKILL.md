---
name: board-config
description: Manage board runtime configuration (language, etc.) stored in .tasks/config.json.
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

## Default language rule

The board's default working language is **English (EN)**. All generated text
(GitHub issue titles/bodies, documentation) is produced in EN unless the user
explicitly overrides it with `board-config --set-language <code>`.
