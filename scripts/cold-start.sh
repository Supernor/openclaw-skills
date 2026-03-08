#!/usr/bin/env bash
# cold-start.sh — Pull core charts for session bootstrap
# Reads the cold-start-bootstrap manifest, then fetches each referenced chart.
# Output: consolidated context block for LLM consumption.
# Intent: Coherent [I19]
set -eo pipefail

echo "=== OPENCLAW COLD START CONTEXT ==="
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Core chart IDs — maintained in chart cold-start-bootstrap
# Update this list when bootstrap chart changes
CORE_CHARTS=(
  # Identity — what you are (read first)
  identity-what-is-openclaw
  identity-harness-not-model
  identity-values-are-architectural
  identity-what-you-means
  identity-closest-name
  identity-personality-by-design
  identity-language-problem
  identity-external-validation
  identity-harness-lock-in
  # Infrastructure — what you can do
  infra-capabilities-master
  infra-google-services-validated
  # Architecture — how you work
  vision-values-harness-2026-03-07
  governance-harness-over-model
  onboarding-start-here
  config-model-routing
  # Operations
  reading-youtube-transcript-pipeline
  procedure-transcript-pipeline
  procedure-idea-pipeline
  procedure-source-registry
  agent-strategy
  decision-python-first
  reading-use-oc-not-docker
  reading-mcp-primary-not-cli
  reading-agent-communication-patterns
)

for chart_id in "${CORE_CHARTS[@]}"; do
  CONTENT=$(chart read "$chart_id" 2>/dev/null | tail -n +5)
  if [ -n "$CONTENT" ]; then
    echo "--- $chart_id ---"
    echo "$CONTENT"
    echo ""
  else
    echo "--- $chart_id --- (NOT FOUND)"
    echo ""
  fi
done

echo "=== Known Issues (from MEMORY.md) ==="
sed -n '/^## Known Issues/,/^##[^#]/p' /root/.claude/projects/-root/memory/MEMORY.md 2>/dev/null | sed '$d'

echo ""
echo "=== END COLD START ==="
