/**
 * model-health-monitor hook
 *
 * Polls auth-profile usageStats across all agents every 30s.
 * Writes model-health.json (atomic) and appends to model-health-notifications.jsonl.
 * Also polls provider usage windows (token limits) for providers that support it.
 */

import fs from "node:fs";
import fsp from "node:fs/promises";
import { execSync } from "node:child_process";
import os from "node:os";
import path from "node:path";

// --- Types ---

interface ProfileUsageStats {
  lastUsed?: number;
  cooldownUntil?: number;
  disabledUntil?: number;
  disabledReason?: string;
  errorCount?: number;
  failureCounts?: Record<string, number>;
  lastFailureAt?: number;
}

interface AuthProfileStore {
  version: number;
  profiles: Record<string, { provider: string; type: string }>;
  usageStats?: Record<string, ProfileUsageStats>;
}

type ProviderStatus = "healthy" | "rate-limited" | "quarantined";
type ProfileStatus = "ok" | "cooldown" | "disabled";

interface ProfileHealthInfo {
  status: ProfileStatus;
  errorCount: number;
  lastUsed?: string;
  cooldownUntil?: string;
  disabledUntil?: string;
  disabledReason?: string;
  failureCounts?: Record<string, number>;
}

interface ProviderHealth {
  status: ProviderStatus;
  reason: string;
  since: string;
  disabledUntil?: string;
  failureCount: number;
  profiles: Record<string, ProfileHealthInfo>;
}

interface UsageWindow {
  label: string;
  usedPercent: number;
  resetAt?: number;
}

interface ProviderUsageSnapshot {
  provider: string;
  displayName: string;
  windows: UsageWindow[];
  plan?: string;
  error?: string;
}

interface ModelHealthState {
  version: 1;
  lastChecked: string;
  providers: Record<string, ProviderHealth>;
  fallbackChain: {
    configured: string[];
    quarantined: string[];
  };
  usage?: {
    lastFetched: string;
    providers: ProviderUsageSnapshot[];
  };
}

interface HealthNotification {
  ts: string;
  type: "failure" | "recovery";
  provider: string;
  reason: string;
  message: string;
}

interface HookEvent {
  type: string;
  action: string;
  sessionKey: string;
  context: Record<string, unknown>;
  timestamp: Date;
  messages: string[];
}

// --- Constants ---

const POLL_INTERVAL_MS = 30_000;
const MAX_NOTIFICATION_LINES = 500;

// --- State ---

let previousProviderStatuses: Record<string, ProviderStatus> = {};
let pollTimer: ReturnType<typeof setInterval> | null = null;

// --- Helpers ---

function getStateDir(): string {
  return process.env.OPENCLAW_STATE_DIR || path.join(os.homedir(), ".openclaw");
}

function log(level: string, msg: string, meta?: Record<string, unknown>): void {
  const prefix = `[model-health-monitor] [${level.toUpperCase()}]`;
  const metaStr = meta ? ` ${JSON.stringify(meta)}` : "";
  console.log(`${prefix} ${msg}${metaStr}`);
}

async function readJsonFile<T>(filePath: string): Promise<T | null> {
  try {
    const raw = await fsp.readFile(filePath, "utf-8");
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

async function atomicWriteJson(filePath: string, data: unknown): Promise<void> {
  const tmpPath = `${filePath}.tmp.${process.pid}`;
  await fsp.writeFile(tmpPath, JSON.stringify(data, null, 2), "utf-8");
  await fsp.rename(tmpPath, filePath);
}

async function appendNotification(filePath: string, notification: HealthNotification): Promise<void> {
  const line = JSON.stringify(notification) + "\n";
  await fsp.appendFile(filePath, line, "utf-8");

  // Rotate if too long
  try {
    const content = await fsp.readFile(filePath, "utf-8");
    const lines = content.trim().split("\n");
    if (lines.length > MAX_NOTIFICATION_LINES) {
      const trimmed = lines.slice(lines.length - MAX_NOTIFICATION_LINES).join("\n") + "\n";
      await fsp.writeFile(filePath, trimmed, "utf-8");
    }
  } catch {
    // ignore rotation errors
  }
}

function extractProvider(profileId: string): string {
  // Profile IDs look like "google:default", "anthropic:default"
  const colon = profileId.indexOf(":");
  return colon > 0 ? profileId.substring(0, colon) : profileId;
}

function deriveProfileStatus(stats: ProfileUsageStats): ProfileStatus {
  const now = Date.now();
  if (stats.disabledUntil && stats.disabledUntil > now) {
    return "disabled";
  }
  if (stats.cooldownUntil && stats.cooldownUntil > now) {
    return "cooldown";
  }
  return "ok";
}

function deriveProviderStatus(profiles: Record<string, ProfileHealthInfo>): {
  status: ProviderStatus;
  reason: string;
} {
  const profileEntries = Object.values(profiles);
  if (profileEntries.length === 0) {
    return { status: "healthy", reason: "none" };
  }

  // If any profile is disabled, provider is quarantined
  const disabled = profileEntries.filter((p) => p.status === "disabled");
  if (disabled.length > 0) {
    const reasons = disabled.map((p) => p.disabledReason).filter(Boolean);
    const reason = reasons[0] || "unknown";
    return { status: "quarantined", reason };
  }

  // If any profile is on cooldown, provider is rate-limited
  const cooldown = profileEntries.filter((p) => p.status === "cooldown");
  if (cooldown.length > 0) {
    return { status: "rate-limited", reason: "rate-limit" };
  }

  // If high error count, treat as rate-limited
  const highError = profileEntries.filter((p) => p.errorCount >= 3);
  if (highError.length > 0) {
    return { status: "rate-limited", reason: "errors" };
  }

  return { status: "healthy", reason: "none" };
}

// --- Core logic ---

async function collectAuthProfiles(stateDir: string): Promise<Map<string, AuthProfileStore>> {
  const agentsDir = path.join(stateDir, "agents");
  const result = new Map<string, AuthProfileStore>();

  try {
    const agents = await fsp.readdir(agentsDir);
    for (const agentId of agents) {
      const profilePath = path.join(agentsDir, agentId, "agent", "auth-profiles.json");
      const store = await readJsonFile<AuthProfileStore>(profilePath);
      if (store) {
        result.set(agentId, store);
      }
    }
  } catch {
    log("warn", "Could not read agents directory");
  }

  return result;
}

function buildProviderHealth(
  allStores: Map<string, AuthProfileStore>,
): Record<string, ProviderHealth> {
  const providers: Record<string, ProviderHealth> = {};
  const now = new Date().toISOString();

  for (const [_agentId, store] of allStores) {
    const stats = store.usageStats ?? {};

    for (const [profileId, profileStats] of Object.entries(stats)) {
      const provider = extractProvider(profileId);

      if (!providers[provider]) {
        providers[provider] = {
          status: "healthy",
          reason: "none",
          since: now,
          failureCount: 0,
          profiles: {},
        };
      }

      const profStatus = deriveProfileStatus(profileStats);

      const profileInfo: ProfileHealthInfo = {
        status: profStatus,
        errorCount: profileStats.errorCount ?? 0,
        lastUsed: profileStats.lastUsed
          ? new Date(profileStats.lastUsed).toISOString()
          : undefined,
        cooldownUntil: profileStats.cooldownUntil
          ? new Date(profileStats.cooldownUntil).toISOString()
          : undefined,
        disabledUntil: profileStats.disabledUntil
          ? new Date(profileStats.disabledUntil).toISOString()
          : undefined,
        disabledReason: profileStats.disabledReason,
        failureCounts: profileStats.failureCounts,
      };

      // Merge — keep worst status per profile across agents
      const existing = providers[provider].profiles[profileId];
      if (!existing || profStatus === "disabled" || (profStatus === "cooldown" && existing.status === "ok")) {
        providers[provider].profiles[profileId] = profileInfo;
      }

      providers[provider].failureCount += profileStats.errorCount ?? 0;
    }
  }

  // Derive provider-level status from profiles
  for (const [providerName, health] of Object.entries(providers)) {
    const derived = deriveProviderStatus(health.profiles);
    health.status = derived.status;
    health.reason = derived.reason;

    // Set disabledUntil to the max across profiles
    const disabledUntils = Object.values(health.profiles)
      .map((p) => p.disabledUntil)
      .filter(Boolean) as string[];
    if (disabledUntils.length > 0) {
      health.disabledUntil = disabledUntils.sort().pop();
    }
  }

  return providers;
}

// --- Usage window fetching ---

async function fetchProviderUsage(stateDir: string): Promise<ProviderUsageSnapshot[]> {
  try {
    // Use openclaw CLI to get structured usage data from supported providers
    const raw = execSync("openclaw models status --all-agents 2>/dev/null || openclaw models status 2>/dev/null", {
      timeout: 15000,
      encoding: "utf-8",
    });

    const snapshots: ProviderUsageSnapshot[] = [];

    // Parse "openai-codex usage: 5h 75% left ⏱1h 42m · Week 93% left ⏱6d 20h" lines
    const usageRegex = /^-\s+([\w-]+)\s+usage:\s+(.+)$/gm;
    let match;
    while ((match = usageRegex.exec(raw)) !== null) {
      const provider = match[1];
      const usageStr = match[2];
      const windows: UsageWindow[] = [];

      // Parse individual windows like "5h 75% left ⏱1h 42m" or "Week 93% left ⏱6d 20h"
      const windowRegex = /([\w]+)\s+(\d+(?:\.\d+)?)%\s+left(?:\s+⏱([\w\s]+))?/g;
      let wMatch;
      while ((wMatch = windowRegex.exec(usageStr)) !== null) {
        const label = wMatch[1];
        const usedPercent = 100 - parseFloat(wMatch[2]);
        windows.push({ label, usedPercent });
      }

      if (windows.length > 0) {
        snapshots.push({ provider, displayName: provider, windows });
      }
    }

    // Also check for status line format: "openai-codex:default ok expires in 6d"
    // and error lines: "openai-codex:default error: ..."
    const profileRegex = /^\s+-([\w-]+):default\s+(ok|error|cooldown|disabled)(.*)$/gm;
    while ((match = profileRegex.exec(raw)) !== null) {
      const provider = match[1];
      const status = match[2];
      const detail = match[3].trim();
      const existing = snapshots.find(s => s.provider === provider);
      if (existing) {
        if (status !== "ok") {
          existing.error = `${status}: ${detail}`;
        }
      } else if (status !== "ok") {
        snapshots.push({ provider, displayName: provider, windows: [], error: `${status}: ${detail}` });
      }
    }

    return snapshots;
  } catch (err) {
    log("warn", `Usage fetch failed: ${err instanceof Error ? err.message : String(err)}`);
    return [];
  }
}

function getConfiguredFallbackChain(stateDir: string): string[] {
  // Source of truth: openclaw.json
  try {
    const configPath = path.join(stateDir, "openclaw.json");
    const raw = fs.readFileSync(configPath, "utf-8");
    const config = JSON.parse(raw);

    const defaultsFallbacks = config?.agents?.defaults?.model?.fallbacks;
    if (Array.isArray(defaultsFallbacks) && defaultsFallbacks.length > 0) {
      return defaultsFallbacks.filter((m: unknown): m is string => typeof m === "string" && m.length > 0);
    }

    const firstAgentFallbacks = config?.agents?.list?.[0]?.model?.fallbacks;
    if (Array.isArray(firstAgentFallbacks) && firstAgentFallbacks.length > 0) {
      return firstAgentFallbacks.filter((m: unknown): m is string => typeof m === "string" && m.length > 0);
    }
  } catch (err) {
    log("warn", `Could not read fallback chain from openclaw.json: ${err instanceof Error ? err.message : String(err)}`);
  }

  return [];
}

function getQuarantinedFromProviders(
  providers: Record<string, ProviderHealth>,
  chain: string[],
): string[] {
  const quarantined: string[] = [];
  for (const model of chain) {
    const provider = model.split("/")[0];
    if (providers[provider]?.status === "quarantined") {
      quarantined.push(model);
    }
  }
  return quarantined;
}

async function pollHealthCheck(stateDir: string): Promise<void> {
  try {
    const allStores = await collectAuthProfiles(stateDir);
    if (allStores.size === 0) {
      log("debug", "No auth profile stores found");
      return;
    }

    const providers = buildProviderHealth(allStores);
    const chain = getConfiguredFallbackChain(stateDir);
    const quarantined = getQuarantinedFromProviders(providers, chain);
    const now = new Date().toISOString();

    // Fetch live provider usage windows (token limits, % remaining) — best effort
    const usageSnapshots = await fetchProviderUsage(stateDir);

    const healthState: ModelHealthState = {
      version: 1,
      lastChecked: now,
      providers,
      fallbackChain: {
        configured: chain,
        quarantined,
      },
      usage: {
        lastFetched: now,
        providers: usageSnapshots,
      },
    };

    const healthPath = path.join(stateDir, "model-health.json");
    const notifyPath = path.join(stateDir, "model-health-notifications.jsonl");

    // Detect state changes and emit notifications
    for (const [providerName, health] of Object.entries(providers)) {
      const prevStatus = previousProviderStatuses[providerName];
      const curStatus = health.status;

      if (prevStatus && prevStatus !== curStatus) {
        if (curStatus === "quarantined" || curStatus === "rate-limited") {
          const notification: HealthNotification = {
            ts: now,
            type: "failure",
            provider: providerName,
            reason: health.reason,
            message: `Provider ${providerName} is now ${curStatus}: ${health.reason}${health.disabledUntil ? ` (until ${health.disabledUntil})` : ""}`,
          };
          await appendNotification(notifyPath, notification);
          log("warn", notification.message);
        } else if (curStatus === "healthy" && (prevStatus === "quarantined" || prevStatus === "rate-limited")) {
          const notification: HealthNotification = {
            ts: now,
            type: "recovery",
            provider: providerName,
            reason: "recovered",
            message: `Provider ${providerName} has recovered (was: ${prevStatus})`,
          };
          await appendNotification(notifyPath, notification);
          log("info", notification.message);
        }
      } else if (!prevStatus && (curStatus === "quarantined" || curStatus === "rate-limited")) {
        // First check detected a problem
        const notification: HealthNotification = {
          ts: now,
          type: "failure",
          provider: providerName,
          reason: health.reason,
          message: `Provider ${providerName} detected as ${curStatus}: ${health.reason}${health.disabledUntil ? ` (until ${health.disabledUntil})` : ""}`,
        };
        await appendNotification(notifyPath, notification);
        log("warn", notification.message);
      }
    }

    // Update previous state
    previousProviderStatuses = {};
    for (const [name, health] of Object.entries(providers)) {
      previousProviderStatuses[name] = health.status;
    }

    // Atomic write health state
    await atomicWriteJson(healthPath, healthState);

    const healthySummary = Object.entries(providers)
      .map(([name, h]) => `${name}=${h.status}`)
      .join(", ");
    log("debug", `Health check complete: ${healthySummary}`);
  } catch (err) {
    log("error", `Health check failed: ${err instanceof Error ? err.message : String(err)}`);
  }
}

// --- Hook handler ---

const handler = async (event: HookEvent): Promise<void> => {
  if (event.type !== "gateway" || event.action !== "startup") {
    return;
  }

  const stateDir = getStateDir();
  log("info", `Starting model health monitor (polling every ${POLL_INTERVAL_MS / 1000}s)`);

  // Run first check immediately
  await pollHealthCheck(stateDir);

  // Start polling interval
  if (pollTimer) {
    clearInterval(pollTimer);
  }
  pollTimer = setInterval(() => {
    pollHealthCheck(stateDir).catch((err) => {
      log("error", `Poll tick failed: ${err instanceof Error ? err.message : String(err)}`);
    });
  }, POLL_INTERVAL_MS);

  // Don't let the interval keep the process alive if gateway shuts down
  if (pollTimer && typeof pollTimer === "object" && "unref" in pollTimer) {
    pollTimer.unref();
  }
};

export default handler;
