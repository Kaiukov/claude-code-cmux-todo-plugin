import { tool } from "@opencode-ai/plugin"
import { fileURLToPath } from "node:url"
import { dirname, resolve, join } from "node:path"
import { existsSync } from "node:fs"

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

export function resolveBinDir() {
  if (process.env.CMUX_BOARD_HOME) {
    const candidate = join(process.env.CMUX_BOARD_HOME, "bin", "board-status")
    if (existsSync(candidate)) return join(process.env.CMUX_BOARD_HOME, "bin")
  }
  let dir = __dirname
  for (let i = 0; i < 10; i++) {
    const candidate = join(dir, "bin", "board-status")
    if (existsSync(candidate)) return join(dir, "bin")
    const parent = dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  return resolve(__dirname, "..", "..", "bin")
}

const BIN = resolveBinDir()

export const CmuxBoardPlugin = async ({ project, client, $, directory, worktree }) => {
  return {
    tool: {
      "board_status": tool({
        description:
          "Get board status counts and next ready task. Reads .tasks/board.json. Optionally include up to N ready task objects.",
        args: {
          readyTasks: tool.schema
            .number()
            .optional()
            .describe("Max ready tasks to include in the output"),
        },
        async execute(args, context) {
          const { directory, $ } = context
          const flag =
            args.readyTasks && args.readyTasks > 0
              ? `--ready-tasks ${args.readyTasks}`
              : ""
          const result =
            await $`"${BIN}/board-status" --json ${flag}`.cwd(directory).quiet()
          return result.stdout.toString()
        },
      }),
      "board_next": tool({
        description:
          "Get the next actionable task for a given status from .tasks/board.json. Defaults to 'ready' status.",
        args: {
          status: tool.schema
            .string()
            .optional()
            .describe(
              "Canonical status filter (inbox, ready, in-progress, needs-review, blocked, needs-info, done). Default: ready"
            ),
        },
        async execute(args, context) {
          const { directory, $ } = context
          const statusArg = args.status ? `--status ${args.status}` : ""
          const result =
            await $`"${BIN}/board-next" --json ${statusArg}`.cwd(directory).quiet()
          return result.stdout.toString()
        },
      }),
    },
    "shell.env": async (input, output) => {
      output.env.BOARD_REPO = process.env.BOARD_REPO || ""
      output.env.CURRENT_TASK = process.env.CURRENT_TASK || ""
    },
    "session.idle": async (_input, _output) => {
      const task = process.env.CURRENT_TASK || ""
      const surface = process.env.SURFACE || ""
      const status = process.env.STATUS || "success"
      const branch = process.env.BRANCH || ""

      if (!task || !surface) return

      const payload = branch
        ? `CTB-DONE task=${task} surface=${surface} status=${status} branch=${branch}`
        : `CTB-DONE task=${task} surface=${surface} status=${status}`

      console.log(payload)

      try {
        await $`cmux notify --title "CTB-DONE" --body "task=${task} surface=${surface} status=${status} branch=${branch}" --surface "${surface}"`.quiet()
      } catch {
        // cmux not available — stdout payload above is the fallback
      }
    },
  }
}
