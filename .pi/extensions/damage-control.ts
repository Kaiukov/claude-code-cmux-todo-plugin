/**
 * damage-control.ts — Pi extension: data-driven deny/ask safety gate for bash
 *
 * Ported from disler/pi-vs-claude-code (MIT).
 * https://github.com/disler/pi-vs-claude-code
 *
 * Loads rules from .pi/damage-control-rules.yaml and enforces them on every
 * bash tool invocation:
 *   deny  → hard block + log the matched rule reason
 *   ask   → confirmation prompt (user must approve)
 *   no match → allow
 *
 * Rules are data-driven — edit the YAML file to add/remove/tune patterns
 * without touching this extension.
 */

import type { ExtensionAPI, ToolCallEvent } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

interface Rule {
  pattern: string;
  reason: string;
  ask?: boolean;
}

interface Rules {
  bashToolPatterns: Rule[];
  zeroAccessPaths: string[];
  readOnlyPaths: string[];
  noDeletePaths: string[];
}

export default function (pi: ExtensionAPI) {
  let rules: Rules = {
    bashToolPatterns: [],
    zeroAccessPaths: [],
    readOnlyPaths: [],
    noDeletePaths: [],
  };

  function resolvePath(p: string, cwd: string): string {
    if (p.startsWith("~")) {
      p = path.join(os.homedir(), p.slice(1));
    }
    return path.resolve(cwd, p);
  }

  function expandTilde(p: string): string {
    return p.startsWith("~") ? path.join(os.homedir(), p.slice(1)) : p;
  }

  // Substring search that only counts a hit when the next char is not a
  // path-word char. Prevents partial-path false positives.
  function commandReferencesPath(command: string, protectedPath: string): boolean {
    if (!protectedPath) return false;
    let idx = command.indexOf(protectedPath);
    while (idx >= 0) {
      const after = command[idx + protectedPath.length];
      if (!after || !/[A-Za-z0-9_-]/.test(after)) return true;
      idx = command.indexOf(protectedPath, idx + 1);
    }
    return false;
  }

  function isPathMatch(targetPath: string, pattern: string, cwd: string): boolean {
    const resolvedPattern = pattern.startsWith("~")
      ? path.join(os.homedir(), pattern.slice(1))
      : pattern;

    if (resolvedPattern.endsWith("/")) {
      const absolutePattern = path.isAbsolute(resolvedPattern)
        ? resolvedPattern
        : path.resolve(cwd, resolvedPattern);
      return targetPath.startsWith(absolutePattern);
    }

    // Convert * to .* for simple glob matching
    const regexPattern = resolvedPattern
      .replace(/[.+^${}()|[\]\\]/g, "\\$&")
      .replace(/\*/g, ".*");
    const regex = new RegExp(
      `^${regexPattern}$|^${regexPattern}/|/${regexPattern}$|/${regexPattern}/`
    );

    const relativePath = path.relative(cwd, targetPath);
    return (
      regex.test(targetPath) ||
      regex.test(relativePath) ||
      targetPath.includes(resolvedPattern) ||
      relativePath.includes(resolvedPattern)
    );
  }

  // ── Load rules on session start ──────────────────────────────────────
  pi.on("session_start", async (_event, ctx) => {
    const projectRulesPath = path.join(ctx.cwd, ".pi", "damage-control-rules.json");
    const globalRulesPath = path.join(os.homedir(), ".pi", "damage-control-rules.json");
    const rulesPath = fs.existsSync(projectRulesPath)
      ? projectRulesPath
      : fs.existsSync(globalRulesPath)
        ? globalRulesPath
        : null;

    try {
      if (rulesPath) {
        const content = fs.readFileSync(rulesPath, "utf8");
        const loaded = JSON.parse(content) as Partial<Rules>;
        rules = {
          bashToolPatterns: loaded.bashToolPatterns || [],
          zeroAccessPaths: loaded.zeroAccessPaths || [],
          readOnlyPaths: loaded.readOnlyPaths || [],
          noDeletePaths: loaded.noDeletePaths || [],
        };
        const source = rulesPath === projectRulesPath ? "project" : "global";
        const total =
          rules.bashToolPatterns.length +
          rules.zeroAccessPaths.length +
          rules.readOnlyPaths.length +
          rules.noDeletePaths.length;
        ctx.ui.notify(
          `🛡️ Damage-Control: Loaded ${total} rules (${source}).`
        );
      } else {
        ctx.ui.notify(
          "🛡️ Damage-Control: No rules found at .pi/damage-control-rules.json (project or global)"
        );
      }
    } catch (err) {
      ctx.ui.notify(
        `🛡️ Damage-Control: Failed to load rules: ${err instanceof Error ? err.message : String(err)}`
      );
    }

    const total =
      rules.bashToolPatterns.length +
      rules.zeroAccessPaths.length +
      rules.readOnlyPaths.length +
      rules.noDeletePaths.length;
    ctx.ui.setStatus(`🛡️ Damage-Control Active: ${total} Rules`);
  });

  // ── Enforce rules on every tool call ─────────────────────────────────
  pi.on("tool_call", async (event, ctx) => {
    let violationReason: string | null = null;
    let shouldAsk = false;

    // 1. Check Zero-Access Paths for path-based tools
    const checkPaths = (pathsToCheck: string[]) => {
      for (const pt of pathsToCheck) {
        const resolved = resolvePath(pt, ctx.cwd);
        for (const zap of rules.zeroAccessPaths) {
          if (isPathMatch(resolved, zap, ctx.cwd)) {
            return `Access to zero-access path restricted: ${zap}`;
          }
        }
      }
      return null;
    };

    const inputPaths: string[] = [];
    if (
      isToolCallEventType("read", event) ||
      isToolCallEventType("write", event) ||
      isToolCallEventType("edit", event)
    ) {
      inputPaths.push(event.input.path);
    } else if (
      isToolCallEventType("grep", event) ||
      isToolCallEventType("find", event) ||
      isToolCallEventType("ls", event)
    ) {
      inputPaths.push(event.input.path || ".");
    }

    if (isToolCallEventType("grep", event) && event.input.glob) {
      for (const zap of rules.zeroAccessPaths) {
        if (
          event.input.glob.includes(zap) ||
          isPathMatch(event.input.glob, zap, ctx.cwd)
        ) {
          violationReason = `Glob matches zero-access path: ${zap}`;
          break;
        }
      }
    }

    if (!violationReason) {
      violationReason = checkPaths(inputPaths);
    }

    // 2. Bash-specific: match command against bashToolPatterns
    if (!violationReason) {
      if (isToolCallEventType("bash", event)) {
        const command = event.input.command;

        for (const rule of rules.bashToolPatterns) {
          const regex = new RegExp(rule.pattern);
          if (regex.test(command)) {
            violationReason = rule.reason;
            shouldAsk = !!rule.ask;
            break;
          }
        }

        // Check if bash command references zero-access paths
        if (!violationReason) {
          for (const zap of rules.zeroAccessPaths) {
            if (command.includes(zap)) {
              violationReason = `Bash command references zero-access path: ${zap}`;
              break;
            }
          }
        }

        // Check if bash command might modify read-only paths
        if (!violationReason) {
          for (const rop of rules.readOnlyPaths) {
            if (
              command.includes(rop) &&
              (/[\s>|]/.test(command) ||
                command.includes("rm") ||
                command.includes("mv") ||
                command.includes("sed"))
            ) {
              violationReason = `Bash command may modify read-only path: ${rop}`;
              break;
            }
          }
        }

        // Check if bash command deletes/moves protected paths
        if (!violationReason) {
          const hasDeleteOrMove =
            /\brm\b/.test(command) || /\bmv\b/.test(command);
          if (hasDeleteOrMove) {
            for (const ndp of rules.noDeletePaths) {
              const expanded = expandTilde(ndp);
              const matched =
                commandReferencesPath(command, ndp) ||
                (expanded !== ndp && commandReferencesPath(command, expanded));
              if (matched) {
                violationReason = `Bash command attempts to delete/move protected path: ${ndp}`;
                break;
              }
            }
          }
        }
      } else if (
        isToolCallEventType("write", event) ||
        isToolCallEventType("edit", event)
      ) {
        // Check read-only paths for write/edit tools
        for (const p of inputPaths) {
          const resolved = resolvePath(p, ctx.cwd);
          for (const rop of rules.readOnlyPaths) {
            if (isPathMatch(resolved, rop, ctx.cwd)) {
              violationReason = `Modification of read-only path restricted: ${rop}`;
              break;
            }
          }
        }
      }
    }

    // 3. Act on violation
    if (violationReason) {
      if (shouldAsk) {
        const confirmed = await ctx.ui.confirm(
          "🛡️ Damage-Control Confirmation",
          `Dangerous command detected: ${violationReason}\n\nCommand: ${isToolCallEventType("bash", event) ? event.input.command : JSON.stringify(event.input)}\n\nDo you want to proceed?`,
          { timeout: 30000 }
        );

        if (!confirmed) {
          ctx.ui.setStatus(
            `⚠️ Last Violation Blocked: ${violationReason.slice(0, 30)}...`
          );
          pi.appendEntry("damage-control-log", {
            tool: event.toolName,
            input: event.input,
            rule: violationReason,
            action: "blocked_by_user",
          });
          ctx.abort();
          return {
            block: true,
            reason: `🛑 BLOCKED by Damage-Control: ${violationReason} (User denied)\n\nDO NOT attempt to work around this restriction. DO NOT retry with alternative commands, paths, or approaches that achieve the same result. Report this block to the user exactly as stated and ask how they would like to proceed.`,
          };
        } else {
          pi.appendEntry("damage-control-log", {
            tool: event.toolName,
            input: event.input,
            rule: violationReason,
            action: "confirmed_by_user",
          });
          return { block: false };
        }
      } else {
        ctx.ui.notify(
          `🛑 Damage-Control: Blocked ${event.toolName} due to ${violationReason}`
        );
        ctx.ui.setStatus(
          `⚠️ Last Violation: ${violationReason.slice(0, 30)}...`
        );
        pi.appendEntry("damage-control-log", {
          tool: event.toolName,
          input: event.input,
          rule: violationReason,
          action: "blocked",
        });
        ctx.abort();
        return {
          block: true,
          reason: `🛑 BLOCKED by Damage-Control: ${violationReason}\n\nDO NOT attempt to work around this restriction. DO NOT retry with alternative commands, paths, or approaches that achieve the same result. Report this block to the user exactly as stated and ask how they would like to proceed.`,
        };
      }
    }

    return { block: false };
  });
}
