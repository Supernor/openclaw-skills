---
name: model-api-speed-test
description: Benchmark model APIs for speed, quality, and stream stability. Configurable for any endpoint.
tags: [benchmark, api, speed, quality, models, nim, gemini, testing]
version: 1.1.0
---

# model-api-speed-test

Test any model API endpoint for speed, output quality, and stream stability. Produces structured data for routing decisions.

## When to use
- Evaluating a new model or provider
- Diagnosing slow agent responses
- After NIM/provider changes or new model releases
- Weekly routing audit (deeper than routing-audit.sh)
- Comparing models before selecting a primary
- Verifying a model swap didn't degrade quality

## Script

`/root/.openclaw/scripts/api-speed-test.py`

## Usage

```bash
# Test specific NIM models
python3 /root/.openclaw/scripts/api-speed-test.py --provider nim --models "mistral-small-4,ministral-14b"

# Test all NIM models
python3 /root/.openclaw/scripts/api-speed-test.py --provider nim --all

# Test Gemini models
python3 /root/.openclaw/scripts/api-speed-test.py --provider gemini --models "gemini-2.5-flash,gemini-2.0-flash"

# Custom prompt (test domain-specific quality)
python3 /root/.openclaw/scripts/api-speed-test.py --provider nim --models "mistral-small-4" --prompt "Write a Python function to parse crontab entries"

# Stream stability only (long response test)
python3 /root/.openclaw/scripts/api-speed-test.py --provider nim --models "mistral-large-3" --stream-only

# Quick reachability check (no quality test)
python3 /root/.openclaw/scripts/api-speed-test.py --provider nim --all --ping-only

# Output as JSON for Bridge display
python3 /root/.openclaw/scripts/api-speed-test.py --provider nim --all --json
```

## Scoring Weights

The overall model score is a weighted composite. These weights reflect what matters most for OpenClaw's use case: reliable streaming to Telegram users on mobile, fast response for interactive menus, and correct structured output for agent tasks.

### Speed (30% of total score)
| Metric | Weight | Rationale |
|--------|--------|-----------|
| Total latency | 15% | End-to-end matters for interactive UX (Tap menus, Bridge) |
| TTFT (time to first token) | 15% | Perceived responsiveness — user sees "typing..." faster |

**Scoring**: <1s = 100, <2s = 80, <3s = 60, <5s = 40, <10s = 20, >10s = 0

### Stream Stability (35% of total score)
| Metric | Weight | Rationale |
|--------|--------|-----------|
| Chars per second (sustained) | 10% | Throughput during active streaming |
| Max gap duration | 15% | The freeze/resume pattern — worst single pause. This is what users feel. |
| Gap count (>2s) | 10% | Frequency of noticeable pauses |

**Scoring (max gap)**: 0s = 100, <1s = 90, <2s = 70, <3s = 50, <5s = 30, <8s = 10, >8s = 0
**Scoring (cps)**: >500 = 100, >300 = 80, >150 = 60, >50 = 40, >20 = 20, <20 = 0

### Quality (25% of total score)
| Metric | Weight | Rationale |
|--------|--------|-----------|
| Structured format compliance | 15% | Can the model follow "list 5 items numbered 1-5"? Agents need this. |
| Response completeness | 10% | Did it answer the full prompt, not just part of it? |

**Scoring (format)**: 5/5 items = 100, 4/5 = 80, 3/5 = 50, <3 = 0

### Reliability (10% of total score)
| Metric | Weight | Rationale |
|--------|--------|-----------|
| Success rate (no errors/timeouts) | 10% | A model that fails 1 in 3 calls wastes tokens on retries |

**Scoring**: Pass = 100, Timeout = 20, Error = 0

### Grade Mapping
| Composite Score | Grade | Recommendation |
|----------------|-------|----------------|
| 85-100 | A | Primary candidate |
| 70-84 | B | Good fallback |
| 50-69 | C | Use for non-critical tasks only |
| 30-49 | D | Avoid — too slow or unreliable |
| 0-29 | F | Broken — disable this route |

### Why these weights?
- **Stream stability is heaviest (35%)** because Robert is phone-first. A 7-second freeze mid-message on Telegram is worse than a 2-second slower initial response. The freeze pattern on Mistral Large was confirmed by benchmark and by Robert's direct experience.
- **Speed is second (30%)** because interactive UX (Tap bot, Bridge) needs sub-2s responses. 5+ seconds makes the UI feel broken.
- **Quality is third (25%)** because all tested models produced identical GOOD quality on structured prompts. Quality only differentiates at the margins — the real differentiator is speed and stability.
- **Reliability is lowest (10%)** because NIM free tier is generally reliable. This weight would increase if we were comparing across providers with different uptime characteristics.

### Benchmark baseline (2026-03-25)
| Model | Speed | Stream | Quality | Reliability | Composite | Grade |
|-------|-------|--------|---------|-------------|-----------|-------|
| Mistral Small 4 (119B) | 80 | 100 | 100 | 100 | **94** | **A** |
| Ministral (14B) | 60 | 100 | 100 | 100 | **89** | **A** |
| Llama 3.3 70B | 100 | 50 | 100 | 100 | **78** | **B** |
| Mistral Medium 3 | 40 | 90 | 100 | 100 | **77** | **B** |
| Mistral Large 3 (675B) | 40 | 40 | 100 | 100 | **60** | **C** |
| DeepSeek V3.2 | 0 | 0 | 0 | 20 | **5** | **F** |

## Output
- Live results to stdout
- JSON to stdout with `--json`
- Appends to `/root/.openclaw/logs/api-speed-test.jsonl` for trend tracking
- Snapshot at `/root/.openclaw/model-benchmark-latest.json`
- Historical at `/root/.openclaw/docs/model-benchmark-YYYY-MM-DD.json`
- Bridge API at `/api/routing-audit`

## Providers
- **nim** — NVIDIA NIM (free tier). Key: `NVIDIA_NIM_API_KEY`
- **gemini** — Google Gemini API (free + paid). Key: `GEMINI_FREE_API_KEY`
- **openai** — OpenAI-compatible endpoints (future)
