# spawn-3x3.sh — cmux 3×3 Pane Grid

Скрипт разворачивает текущий cmux-воркспейс в чистую сетку панелей 3×3 (9 терминалов).
Терминал, из которого запущен скрипт, становится top-left панелью — все остальные
панели создаются вокруг него, старые закрываются.

**Файл:** `spawn-3x3.sh` (корень репозитория)

## Использование

```bash
./spawn-3x3.sh
```

Никаких аргументов. Скрипт сам определяет текущий воркспейс и поверхность через
`cmux identify --json`.

## Что делает

1. **Определяет контекст** — workspace + surface вызывающего терминала
2. **Зачищает старые панели** — закрывает все поверхности в воркспейсе, кроме своей
3. **Строит сетку 3×3** — последовательными `new-split right` / `new-split down`:

```
surface (ты)  |  new-split right  |  new-split right
new-split down | new-split down   | new-split down
new-split down | new-split down   | new-split down
```

Все сплит-команды идут с `--focus false` — фокус остаётся на пользовательском
терминале.

4. **Итог:** 9 панелей, ровная сетка, ничего лишнего.

## Как работает (детали)

### Определение контекста

Скрипт **не полагается на `$CMUX_WORKSPACE_ID` / `$CMUX_SURFACE_ID`**,
потому что эти переменные могут содержать UUID вместо коротких refs
(`workspace:N` / `surface:N`). UUID ломает сравнение при зачистке старых панелей.

Вместо этого всегда вызывается `cmux identify --json` и извлекаются поля
`caller.workspace_ref` и `caller.surface_ref` — они гарантированно в формате
коротких refs.

### Зачистка старых панелей

`cmux list-panes --workspace <ws> --json` → итерация по всем `surface_refs`.
Все поверхности, кроме `caller.surface_ref`, закрываются через `cmux close-surface`.
После этого в воркспейсе остаётся ровно 1 панель с 1 поверхностью.

### Построение сетки

Порядок сплитов важен — от него зависит, какие surface/pane ID присвоит cmux:

| Шаг | Команда | Результат |
|-----|---------|-----------|
| 1 | `new-split right` на caller surface | top-mid поверхность |
| 2 | `new-split right` на top-mid | top-right поверхность |
| 3 | `new-split down` на top-left (caller) | mid-left |
| 4 | `new-split down` на top-mid | mid-mid |
| 5 | `new-split down` на top-right | mid-right |
| 6 | `new-split down` на mid-left | bot-left |
| 7 | `new-split down` на mid-mid | bot-mid |
| 8 | `new-split down` на mid-right | bot-right |

Каждый `new-split` возвращает `OK surface:N workspace:M` — из этого ответа
grep-ом извлекается ref новой поверхности для следующего шага.

## Баги и фиксы

### UUID vs ref mismatch (исправлен)

**Симптом:** скрипт закрывал все поверхности включая свою, агент терял терминал.

**Причина:** `$CMUX_SURFACE_ID` содержал UUID (`09CE9392-...`),
а `list-panes` возвращал `surface:N`. Сравнение `"surface:159" != "UUID"` всегда true,
зачистка убивала всё.

**Фикс:** всегда получать refs через `cmux identify --json`, не через env vars.

### close-surface возвращает чужие ID (не влияет)

`cmux close-surface --surface surface:N` иногда возвращает `OK surface:M`,
где M ≠ N. Это cmux-специфичное поведение (вероятно, следующий доступный ID),
на логику скрипта не влияет — поверхность всё равно закрывается.

## Интеграция с плагином

Скрипт находится в корне репозитория `claude-code-cmux-todo-plugin` и может
использоваться как утилита для быстрого разворачивания рабочей раскладки.

Идеи для будущего:

- **`/board-grid`** — skill, вызывающий `spawn-3x3.sh` и раскладывающий ready-таски
  по панелям сетки
- **Автосетка при `/board-run-ready`** — если тасков > N, развернуть сетку
  и диспатчить параллельно
- **N×M grid** — параметризовать размер сетки: `./spawn-grid.sh 2 4` и т.д.
