---
name: build-deployer
description: Detect project type, deploy it, return test URL accessible from any device.
tags: [build, deploy, workshop]
version: 1.0.0
---

# /build-deployer — Deploy and Return Test Link

## When to use
- After build and review complete
- When the success test requires a URL

## Input
- Project directory with built files
- Available port number

## Output
- JSON: {"url": "http://...", "type": "flask|static|node", "pid": 12345}
- Or: {"url": null, "type": "none", "reason": "no servable content detected"}

## Execution

```bash
python3 /root/.openclaw/scripts/deploy-project.py {dir} --port {port}
```

## Detection Priority
1. Python with Flask/FastAPI/app.run → pip install deps, run seed.py, serve on port
2. HTML files → python3 -m http.server
3. package.json with start script → npm install, npm start with PORT env
4. None detected → return null URL

## Rules
- URL must be accessible from phone (bind 0.0.0.0, use VPS public IP)
- Install dependencies before starting (requirements.txt, package.json)
- Run seed scripts if they exist
- Log server output to /tmp/build-serve-{port}.log

## Files
- Script: `/root/.openclaw/scripts/deploy-project.py`
