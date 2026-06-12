# Pi Role Profiles

Pi ships with five built-in role profiles. Each is a pure configuration mapping
to `{provider, model, thinking, tools}` for `pi --provider … --model … --thinking … --tools …`.

| Profile       | Provider     | Model                | Thinking | Tools                              | When to use                              |
|---------------|--------------|----------------------|----------|------------------------------------|------------------------------------------|
| `backend`     | opencode-go  | deepseek-v4-pro      | high     | read,bash,edit,write,grep,find,ls  | Heavy backend logic, refactors, systems |
| `frontend`    | anthropic    | claude-sonnet-4-6    | medium   | read,bash,edit,write,grep,find,ls  | UI code, styling, component work        |
| `frontend-top`| anthropic    | claude-opus-4-8      | medium   | read,bash,edit,write,grep,find,ls  | Complex frontend architecture, hard UI bugs |
| `review`      | openai-codex | gpt-5.4              | high     | read,bash,grep,find,ls             | Code review, diff analysis, audits      |
| `docs`        | opencode-go  | deepseek-v4-flash    | low      | read,bash,edit,write,grep,find,ls  | Documentation, markdown, prose          |

## Resolution

`board-config --get-profile <name>` resolves a profile. It reads
`.tasks/config.json` → `.profiles.<name>` overrides (deep-merge per field:
any omitted field keeps its built-in default), falling back to the built-in
table above. Override one field without losing the rest:

```json
{ "profiles": { "backend": { "thinking": "medium" } } }
```

## Spawn

`agent-spawn.sh --profile <name>` launches a Pi worker from a profile.
