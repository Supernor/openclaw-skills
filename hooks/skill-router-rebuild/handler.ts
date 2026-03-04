/**
 * skill-router-rebuild hook
 *
 * Rebuilds the skill-router index on gateway:startup so the routing
 * index is always current after restarts or skill additions.
 */

import { execSync } from "node:child_process";
import path from "node:path";
import os from "node:os";

interface HookEvent {
  type: string;
  action: string;
}

function getStateDir(): string {
  return process.env.OPENCLAW_STATE_DIR || path.join(os.homedir(), ".openclaw");
}

function log(level: string, msg: string): void {
  const ts = new Date().toISOString();
  const line = JSON.stringify({ ts, hook: "skill-router-rebuild", level, msg });
  if (level === "error") {
    process.stderr.write(line + "\n");
  } else {
    process.stdout.write(line + "\n");
  }
}

const handler = async (event: HookEvent): Promise<void> => {
  if (event.type !== "gateway" || event.action !== "startup") {
    return;
  }

  const stateDir = getStateDir();
  const scriptPath = path.join(stateDir, "scripts", "skill-router.sh");

  try {
    log("info", "Rebuilding skill-router index...");
    const result = execSync(`bash "${scriptPath}" build`, {
      encoding: "utf-8",
      timeout: 15000,
      env: { ...process.env, HOME: os.homedir() },
    });
    log("info", `Skill-router rebuild complete: ${result.trim()}`);
  } catch (err) {
    log("error", `Skill-router rebuild failed: ${err instanceof Error ? err.message : String(err)}`);
  }
};

export default handler;
