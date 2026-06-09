# Ожидание агентов без `sleep` (cmux events / feed)

Вместо `sleep N` + повторный `agent-screen` — подписка на поток событий cmux.
Оркестратор пробуждается ровно тогда, когда агент закончил ход.

## TL;DR

```bash
# заблокироваться, пока opencode-агент в surface:328 не уйдёт в idle:
cmux events --category agent --category feed --no-heartbeat \
  | grep -m1 -E '"surface_id":"[^"]*328[^"]*".*idle|idle.*328' \
  && echo "AGENT DONE"
```

Запускай это через Bash с `run_in_background: true`. `grep -m1` выходит на
первом совпадении → закрывает пайп → `cmux events` получает SIGPIPE и завершается
→ harness присылает уведомление о завершении фоновой команды. Никакого поллинга.

## Почему не `sleep`

- `sleep`-цикл жжёт токены (каждый `agent-screen` — отдельный вызов) и время.
- Поток событий доставляет точный момент завершения. Точнее и дешевле.

## Предусловие: плагины opencode (ВАЖНО)

Opencode-агенты **не шлют ничего** в cmux, пока не установлены плагины:

```
~/.config/opencode/plugins/cmux-session.js   # lifecycle (running/idle/needsInput) + restore
~/.config/opencode/plugins/cmux-feed.js      # feed: approvals / questions / telemetry
```

Установка (неинтерактивно — голый `cmux hooks setup` лишь печатает превью с y/N):

```bash
yes | cmux hooks opencode install            # session
yes | cmux hooks opencode install --feed     # feed
ls -1 ~/.config/opencode/plugins/            # проверка: оба .js на месте
```

Плагины действуют только на агентов, **запущенных после** установки. Уже
работающий агент событий слать не начнёт — переспавни его.

Codex-агенты ставят свои хуки одной командой:

```bash
yes | cmux hooks codex install               # hooks.json + config.toml
```

Codex-хуки включают lifecycle (SessionStart/Stop → running/idle) и Feed-bridge
(PermissionRequest, PreToolUse → approvals). Отдельного `--feed` флага нет —
codex шлёт approvals через `hooks feed --source codex`.

Claude Code хуки инжектятся автоматически через wrapper (отдельно ставить не надо).

## Как устроен поток

```
opencode-агент ──plugin──▶ cmux socket ──▶ events.stream ──▶ cmux events (CLI)
                                          └─▶ ~/.cmuxterm/events.jsonl (аудит)
                                          └─▶ Feed sidebar + нативные нотификации
```

- Категории: `agent`, `feed`, `notification`, `window`, `workspace`, `pane`, `surface`.
- `agent.hook.<HookEventName>` — нативные события агента.
- Lifecycle агента: `running` → `idle` (ход завершён) / `needsInput` (ждёт ответа).
- Полный аудит-лог: `~/.cmuxterm/events.jsonl` (JSONL, для catch-up).

## Шаг 1. Узнать точное имя idle-события (один раз на сетапе)

Имена событий зависят от версии плагина. Подсмотри их вживую, пока агент работает:

```bash
# в одном окне — слушаем
cmux events --category agent --category feed --no-heartbeat \
  | jq -rc '{name, source, surface: .surface_id, life: .payload.lifecycle}'
```

Дай агенту задачу и смотри, какое событие приходит в момент завершения хода
(ищи `lifecycle":"idle"` или `agent.hook.Stop`/аналог для opencode). Зафиксируй
имя/поле — дальше фильтруешь именно по нему.

Быстрый разбор последних событий из лога (без живого стрима):

```bash
tail -300 ~/.cmuxterm/events.jsonl \
  | jq -rc 'select(.category=="agent") | {name, source, life: .payload.lifecycle}' \
  | sort | uniq -c
```

## Шаг 2. Блокирующее ожидание конкретного surface

```bash
# фон (Bash run_in_background: true). SURF — числовой id, напр. 328
SURF=328
cmux events --category agent --no-heartbeat \
  | jq -rc --arg s "$SURF" \
      'select((.surface_id // "") | test($s)) | select(.payload.lifecycle=="idle") | .surface_id' \
  | head -1
# head -1 завершит пайп на первом idle → команда выходит → приходит нотификация
```

Когда фоновая команда завершилась — агент закончил. Дальше проверяй результат
по факту (git push в ветку, `gh pr checks`), а не по экрану агента:

```bash
git fetch origin <branch> --quiet
git log origin/<branch> --oneline -2
gh pr checks <PR#>
```

## Шаг 3 (опц.). Долгий fallback, если событие не пришло

Если плагин не сработал или агент завис, поток будет молчать. Дай команде
таймаут, чтобы не висеть вечно:

```bash
SURF=328
timeout 1800 bash -c '
  cmux events --category agent --no-heartbeat \
    | jq -rc --arg s "'"$SURF"'" "select((.surface_id // \"\")|test(\$s)) | select(.payload.lifecycle==\"idle\")" \
    | head -1
'
echo "exit=$?"   # 124 = таймаут (агент завис → проверь вручную)
```

## Интерактивные решения агента (Feed)

Если агент задаёт вопрос / просит разрешение (`needsInput`), это приходит в
категорию `feed` как `feed.item.received`. Ответ — через Feed UI (`Ctrl-4` или
`cmux feed tui`) или inline-кнопки нотификации. В headless-оркестрации лучше
давать агентам `--yolo`, чтобы они не упирались в approval.

## Шпаргалка команд

| Задача | Команда |
|---|---|
| Установить хуки opencode | `yes \| cmux hooks opencode install [--feed]` |
| Проверить плагины | `ls -1 ~/.config/opencode/plugins/` |
| Живой поток agent+feed | `cmux events --category agent --category feed --no-heartbeat` |
| Поток с резюмом по курсору | `cmux events --cursor-file ~/.cache/cmux/ev.seq --reconnect` |
| Разбор аудит-лога | `tail -N ~/.cmuxterm/events.jsonl \| jq ...` |
| Ждать idle конкретного surface | см. Шаг 2 (фон + `head -1`) |

## Связанные заметки

- Провайдер для спавна: `opencode-go/deepseek-v4-{pro,flash}` (не `deepseek/...`).
- Док cmux: `cmux docs agents`, и raw — `docs/{events,feed,agent-hooks}.md`
  в репо `manaflow-ai/cmux`.
