---
name: skill-router-rebuild
description: "Rebuild skill-router index on gateway startup"
metadata:
  {
    "openclaw":
      {
        "events": ["gateway:startup"],
        "always": true,
      },
  }
---

# skill-router-rebuild

Runs `skill-router.sh build` when the gateway starts so the routing index
is always fresh. No manual rebuild needed after adding skills or agents.
