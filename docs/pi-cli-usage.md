# Pi CLI Usage Guide

This guide is pinned to `pi` version `0.79.1` from `/opt/homebrew/bin/pi`.
The binary identifies itself as “AI coding assistant with read, bash, edit,
write tools.”

## 1. Overview

`pi` is an interactive coding assistant and a lightweight runtime for agent
work. It can run in a terminal, emit machine-readable output, and load
extensions, skills, templates, and themes.

From `pi --help`:

- Default provider is `google`.
- Output modes are `text` (default), `json`, and `rpc`.
- Extensions can add extra flags of their own.
- Built-in tools are `read`, `bash`, `edit`, `write`, `grep`, `find`, and `ls`.

## 2. Install / Update / Remove

All source forms below come from `pi install --help`:

- `npm:pkg-name`
- `git:github.com/user/repo`
- `git:git@github.com:user/repo`
- `https://github.com/user/repo`
- `ssh://git@github.com/user/repo`
- local paths such as `./local/path`

Examples and forms:

```bash
pi install npm:@foo/bar
pi install git:github.com/user/repo
pi install git:git@github.com:user/repo
pi install https://github.com/user/repo
pi install ssh://git@github.com/user/repo
pi install ./local/path
pi install npm:@foo/bar -l
```

`-l, --local` installs into project-local `.pi/settings.json` instead of the
user settings area.

`-a, --approve` trusts project-local files for the command. `-na, --no-approve`
forces the opposite.

`remove` and `uninstall` are the same operation:

```bash
pi remove npm:@foo/bar
pi remove npm:@foo/bar -l
pi uninstall npm:@foo/bar
pi uninstall npm:@foo/bar -l
```

`update` supports updating everything, one package, or Pi itself:

```bash
pi update
pi update self
pi update pi
pi update npm:@foo/bar
pi update --self
pi update --extensions
pi update --extension npm:@foo/bar
pi update --force
```

`list` shows installed packages from user and project settings:

```bash
pi list
pi list --no-approve
```

`config` opens the TUI that lets you enable or disable package resources:

```bash
pi config
```

## 3. Run Modes

| Mode | Command form | When to use |
| --- | --- | --- |
| Interactive | `pi ...` | Default terminal use. Good for back-and-forth coding help with tools enabled. |
| JSON | `pi --mode json ...` | Use when another process needs structured output instead of human-facing text. |
| RPC | `pi --mode rpc ...` | Use for programmatic integrations that speak the RPC transport. |
| Print | `pi --print ...` or `pi -p ...` | Non-interactive one-shot runs. Process a prompt and exit. |
| SDK | The `rpc` / tool-contract surface | Use when embedding Pi inside another program or agent that wants the tool interface rather than a chat shell. |

Examples:

```bash
pi "List all .ts files in src/"
pi --mode json "Summarize package.json"
pi --mode rpc "Explain this repo"
pi -p "List all .ts files in src/"
```

## 4. Providers & Models

`pi --help` exposes these flags:

- `--provider <name>`: provider name, default `google`
- `--model <pattern>`: model pattern or ID
- `--api-key <key>`: explicit API key override
- `--thinking <level>`: `off`, `minimal`, `low`, `medium`, `high`, or `xhigh`

`--model` accepts both a plain model ID and `provider/id` form. The help also
shows a thinking shorthand with `:<thinking>`:

```bash
pi --provider openai --model gpt-4o-mini "Help me refactor this code"
pi --model openai/gpt-4o "Help me refactor this code"
pi --model sonnet:high "Solve this complex problem"
pi --thinking high "Solve this complex problem"
```

Confirmed provider IDs from the commands I ran:

- `anthropic`
- `deepseek`
- `openai`
- `openai-codex`
- `opencode`
- `opencode-go`
- `zai`

`google-vertex` was not surfaced by the live `pi --list-models` output on this
machine, so I have not treated it as confirmed here.

`pi --list-models` on this machine showed many model IDs under those providers,
including `claude-*`, `deepseek-v4-*`, `gpt-5*`, `kimi-k2.*`, `mimo-*`,
`qwen3.*`, and others. If you need the full live model catalog, rerun:

```bash
pi --list-models
```

If `--api-key` is omitted, Pi looks for provider-specific environment
variables. The help output lists many of them, including:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `DEEPSEEK_API_KEY`
- `GEMINI_API_KEY`
- `OPENCODE_API_KEY`
- `CLOUDFLARE_API_KEY`
- `AWS_ACCESS_KEY_ID`

## 5. Adding Provider Accounts

Pi `pi --help` does not expose a dedicated `login` or `auth` subcommand, so
the exact onboarding flow is only partially verifiable from the commands I ran.
Where the command is confirmed, I show it; where it is not, I mark it
`unverified`.

### `opencode-go`

- Provider id: `opencode-go`
- Auth type: `api_key`
- Verified non-interactive add step:

```bash
pi --provider opencode-go --api-key "$OPENCODE_API_KEY" --model deepseek-v4-pro -p "ping"
```

- Verified runtime check:

```bash
pi --provider opencode-go --model deepseek-v4-pro -p "ping"
```

- `auth.json` shape:

```json
{
  "opencode-go": {
    "type": "api_key",
    "key": "…"
  }
}
```

- Interactive add step: `unverified`

### `openai-codex`

- Provider id: `openai-codex`
- Auth type: `api_key`
- Verified non-interactive add step:

```bash
pi --provider openai-codex --api-key "$OPENAI_API_KEY" --model gpt-5.4 -p "ping"
```

- Interactive add step: `unverified`; Pi help does not show a login command
- Verified runtime check:

```bash
pi --provider openai-codex --model gpt-5.4 -p "ping"
```

This returned `pong` in my probe.

- `auth.json` shape:

```json
{
  "openai-codex": {
    "type": "api_key",
    "key": "…"
  }
}
```

### `anthropic`

- Provider id: `anthropic`
- Auth type: `oauth` `unverified`
- Verified runtime check:

```bash
pi --provider anthropic --model claude-opus-4-6 -p "ping"
```

This reached Anthropic and returned the quota message:

```text
Third-party apps now draw from your extra usage, not your plan limits.
```

- Non-interactive `--api-key` add step: `unverified` / not confirmed by `pi --help`
- Interactive add step: `unverified`; Pi help does not show a login command
- `auth.json` shape:

```json
{
  "anthropic": {
    "type": "oauth",
    "refresh": "…",
    "access": "…",
    "expires": 1735689600000
  }
}
```

### Default provider and model

The task spec calls for `settings.json` fields named `defaultProvider` and
`defaultModel`. Pi help does not document them directly, so treat this as a
project-level convention unless your local `settings.json` already confirms
otherwise.

```json
{
  "defaultProvider": "openai-codex",
  "defaultModel": "gpt-5.4"
}
```

## 6. Config & Files

`pi config` opens a TUI for enabling and disabling package resources.

By default, Pi stores its agent state under `~/.pi/agent/`. The help output
maps that directory through `PI_CODING_AGENT_DIR`, and the task spec requires
these locations:

- `~/.pi/agent/settings.json`
- `~/.pi/agent/auth.json`
- `~/.pi/agent/trust.json`
- `~/.pi/agent/sessions/`

Relevant environment variables from `pi --help`:

- `PI_CODING_AGENT_DIR` - config directory override
- `PI_CODING_AGENT_SESSION_DIR` - session storage override
- `PI_PACKAGE_DIR` - package directory override for Nix/Guix-style layouts

`--session-dir` overrides the session directory for a single run.

## 7. Packages

Pi packages are declared in `package.json` through the `pi` field.

Operational rules:

- Runtime dependencies belong in `dependencies`, not `devDependencies`, so a
  production install still has them available.
- Pi auto-discovers extensions from `~/.pi/agent/extensions/`.
- Pi also auto-discovers extensions from the project-local `.pi/extensions/`
  directory.

Treat the `pi` field as the package manifest for the assistant/runtime layer
and `dependencies` as the install surface for code that must exist at runtime.

## 8. Spawning an Agent from a Terminal in cmux

The direct terminal recipe is:

```bash
SPLIT_OUT="$(cmux new-split right 2>&1)"
SURFACE="$(printf '%s\n' "$SPLIT_OUT" | grep -oE 'surface:[0-9]+' | head -1)"
cmux send --surface "$SURFACE" -- 'pi --provider opencode-go --model deepseek-v4-pro "Audit this repo"'
cmux send-key --surface "$SURFACE" Enter
```

`cmux new-split <left|right|up|down>` creates the pane. `cmux send` types the
launch command into that shell, and `cmux send-key` submits it.

To steer a running agent:

```bash
cmux read-screen --surface "$SURFACE" --lines 40
cmux send --surface "$SURFACE" -- 'git status'
cmux send-key --surface "$SURFACE" Enter
```

The bundled helper lives at:

```bash
plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-spawn.sh
```

Its usage line is:

```bash
agent-spawn.sh <dir> <worktree> <model> [label] [extra agent args...] [--agent opencode|codex]
```

Examples from the helper:

```bash
agent-spawn.sh right "$WT" opencode-go/deepseek-v4-pro TASK
agent-spawn.sh right "$WT" gpt-5.4 TASK -c model_reasoning_effort=high --agent codex
```

The same workflow is what the helper automates:

- `cmux new-split` to create the pane
- `cmux send --surface <ref> -- "<launch cmd>"` to type the launch command
- `cmux send-key --surface <ref> Enter` to execute it
- `cmux read-screen --surface <ref>` to inspect the pane when steering
