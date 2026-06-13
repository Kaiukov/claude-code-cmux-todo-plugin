# Pi Role Profiles

Pi ships with nine built-in profiles. Each is a pure configuration mapping
to `{role, provider, model, thinking, tools}` for `pi --provider … --model … --thinking … --tools …`.

The **role** field decouples the profile name from the prompt-asset filename.
A profile's `role` selects which `prompts/pi/roles/<role>.md` asset is loaded
as the worker's Layer-2 system prompt. This allows multiple profiles (e.g.
`backend-fast`, `test`, `tiny-patch`) to share the `backend` role asset
without requiring duplicate or symlinked files.

| Profile        | Role         | Provider     | Model                 | Thinking | Tools                              | Status   | When to use                              |
|----------------|--------------|--------------|-----------------------|----------|------------------------------------|----------|------------------------------------------|
| `backend`      | backend      | opencode-go  | deepseek-v4-pro       | high     | read,bash,edit,write,grep,find,ls  | verified | Heavy backend logic, refactors, systems |
| `backend-fast` | backend      | opencode     | deepseek-v4-flash-free | low      | read,bash,edit,write,grep,find,ls  | verified | Quick backend fixes, fast turnaround     |
| `repo-scout`   | review       | opencode     | nemotron-3-ultra-free  | medium   | read,bash,grep,find,ls             | verified | Read-only repo exploration, code search  |
| `docs`         | docs         | opencode     | mimo-v2.5-free         | low      | read,bash,edit,write,grep,find,ls  | verified | Documentation, markdown, prose           |
| `test`         | backend      | openai-codex | gpt-5.4-mini           | medium   | read,bash,edit,write,grep,find,ls  | verified | Test writing and test fixes              |
| `tiny-patch`   | backend      | openai-codex | gpt-5.4-mini           | low      | read,bash,edit,write,grep,find,ls  | verified | Single-file patches, trivial changes     |
| `review`       | review       | opencode-go  | deepseek-v4-pro        | high     | read,bash,grep,find,ls             | verified | Code review, diff analysis, audits       |
| `frontend`     | frontend     | anthropic    | claude-sonnet-4-6      | medium   | read,bash,edit,write,grep,find,ls  | TBC      | UI code, styling, component work         |
| `frontend-top` | frontend-top | anthropic    | claude-opus-4-8        | high     | read,bash,edit,write,grep,find,ls  | TBC      | Complex frontend architecture, hard UI bugs |

### Role-to-asset mapping

| Role          | Asset file                          | Used by profiles                                    |
|---------------|-------------------------------------|-----------------------------------------------------|
| `backend`     | `prompts/pi/roles/backend.md`       | backend, backend-fast, test, tiny-patch             |
| `docs`        | `prompts/pi/roles/docs.md`          | docs                                                |
| `frontend`    | `prompts/pi/roles/frontend.md`      | frontend                                            |
| `frontend-top`| `prompts/pi/roles/frontend-top.md`  | frontend-top                                        |
| `review`      | `prompts/pi/roles/review.md`        | review, repo-scout                                  |

## Resolution

`board-config --get-profile <name>` resolves a profile. It reads
`.tasks/config.json` → `.profiles.<name>` overrides (deep-merge per field:
any omitted field keeps its built-in default), falling back to the built-in
table above. Override one field without losing the rest:

```json
{ "profiles": { "backend": { "thinking": "medium" } } }
```

The `--role` selector prints the role field only, mirroring `--provider`,
`--model`, `--thinking`, and `--tools`.

## Spawn

`agent-spawn.sh --profile <name>` launches a Pi worker from a profile.
The spawn helper reads the profile's `role` field and loads the matching
`prompts/pi/roles/<role>.md` as the Layer-2 system prompt asset.
