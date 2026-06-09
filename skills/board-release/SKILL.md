---
name: board-release
description: Stack-agnostic SemVer release helper. Bump versions, create git tags, and publish GitHub Releases with opt-in network safety gates.
---

# board-release

Stack-agnostic SemVer release helper. Detects node, python, go, or unknown
stacks, bumps versions in source files, and creates git tags and GitHub Releases.

NEVER overwrites an existing tag. Network steps (push, gh release create) are
opt-in via `--push`.

```
/board-release --current [-C DIR]
/board-release --bump major|minor|patch [-C DIR]
/board-release --release [major|minor|patch] [--notes NOTES] [--push] [-C DIR]
/board-release --changelog [--version V] [--date D] [--added CSV] [--fixed CSV] [--changed CSV] [-C DIR]
```

## SemVer model

The command follows [Semantic Versioning 2.0.0](https://semver.org):

- **major** — breaking changes (e.g. `1.2.3` → `2.0.0`).
- **minor** — new features, backward-compatible (e.g. `1.2.3` → `1.3.0`).
- **patch** — bug fixes only (e.g. `1.2.3` → `1.2.4`).

Version sources (read AND written):

| Stack    | Source                                   | Write target         |
| -------- | ---------------------------------------- | -------------------- |
| node     | `package.json` → `.version`              | `package.json`       |
| python   | `pyproject.toml` → `version = "..."`    | `pyproject.toml` (or `__version__` file) |
| go       | latest git tag (`vX.Y.Z`)               | *(git tag only)*     |
| unknown  | latest git tag (`vX.Y.Z`)               | *(git tag only)*     |

## Safety gates (release flow)

1. **Clean working tree** — `git diff` + `git diff --cached` must be empty.
   The safety check runs BEFORE any file modifications.
2. **Never overwrite a tag** — if `vX.Y.Z` already exists, the command aborts.
3. **Network opt-in** — `git push` and `gh release create` only run when
   `--push` is explicitly passed. Without `--push`, the release is local only
   (commit + annotated tag).

## Usage notes

- `-C DIR` / `--dir DIR` — operate in a specific directory (default: `.`).
- `--release` optionally takes a bump type (`major|minor|patch`). If omitted,
  the current version is released as-is.
- When `--release` bumps, it writes the new version to the source file before
  committing — no separate `--bump` call needed.
- `--bump` bumps the version in source files only; no git operations.
- `--current` prints the detected stack and current version.
- `--changelog` prepends an entry to `CHANGELOG.md`. If `--version` is omitted,
  the current version is read from the stack. If `--date` is omitted, today's
  UTC date is used.
