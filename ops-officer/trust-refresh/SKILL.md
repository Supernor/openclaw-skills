# SKILL.md — Trust Refresh

## Purpose
The `trust-refresh.sh` script refreshes trust scores for agents, nodes, or services in the OpenClaw fleet. It ensures trust metrics reflect the current state of reliability, responsiveness, and compliance with expected behaviors.

## Schedule
- **Automated**: Runs periodically (e.g., hourly or daily) via cron or scheduled tasks.
- **Event-triggered**: Runs after health checks, incident resolutions, or log audits.
- **Manual**: Can be executed manually by administrators or other scripts.

## Inputs/Outputs
### Inputs
- **Logs**: Gateway logs (`/var/log/openclaw/gateway.log`) or agent-specific logs.
- **Health metrics**: Data from health checks (e.g., `mcp-health-check.sh`).
- **Trust database**: File or database storing trust scores (e.g., `/home/node/.openclaw/trust/scores.json` or `ops.db`).
- **Environment variables**: Configuration values (e.g., `TRUST_DECAY_RATE`, `TRUST_THRESHOLD`).

### Outputs
- **Updated trust scores**: Written back to the trust database.
- **Logs**: Outputs to `/var/log/openclaw/trust-refresh.log` or syslog.
- **Notifications**: Posts updates to `#ops-changelog` or `#ops-dashboard`.

## Trust Score Logic
Trust scores are calculated using:
- **Weighted metrics**: Reliability (uptime, success rate), responsiveness (latency), and compliance (policy adherence).
- **Decay factor**: Scores decay over time if not refreshed (e.g., `trust_score = trust_score * DECAY_RATE + recent_performance`).
- **Thresholds**: Scores below a threshold trigger alerts or remedial actions (e.g., quarantine or rerouting).
- **Normalization**: Scores are normalized to a scale (e.g., 0-100 or 0.0-1.0).

## Trends Over Time
- **Historical tracking**: Trust scores are logged over time to identify trends.
- **Rolling averages**: Used to smooth out short-term fluctuations.
- **Incident correlation**: Trust scores are correlated with incidents to identify patterns.
- **Visualization**: Trends are displayed in dashboards or reports (e.g., `#ops-dashboard` or `#ops-nightly`).

## Failure Modes
- **Silent failure**: Trust scores become stale or inaccurate.
- **Partial failure**: Some scores update while others fail, causing inconsistencies.
- **Recovery**:
  - Errors are logged to `/var/log/openclaw/trust-refresh.log`.
  - Notifications are sent to `#ops-errors` or `#ops-incidents`.
  - Manual intervention may be required to rerun the script or update scores.

## Procedure
To manually run the trust refresh script:
```bash
sudo /root/.openclaw/scripts/trust-refresh.sh
```

## Related Skills
- `log-audit`: Audits logs for errors and trends.
- `incident-manager`: Tracks and resolves incidents.
- `dashboard-update`: Updates the ops dashboard with trust score trends.