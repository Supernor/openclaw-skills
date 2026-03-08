---
name: social-graphic
description: Create social media graphics and banners using AI image generation. Sized for specific platforms.
version: 1.0.0
author: designer
tags:
  - social media
  - graphic
  - banner
  - instagram
  - facebook
  - twitter
  - marketing
  - design
  - visual
trigger:
  command: /social-graphic
  keywords:
    - social media graphic
    - social post image
    - banner image
    - marketing graphic
---

# social-graphic

Generate social media graphics sized for specific platforms.

## Inputs
- Platform (Instagram, Facebook, Twitter/X, LinkedIn)
- Content/message
- Brand palette (from Chartroom or provided)
- Style direction

## Procedure
1. Pull brand palette from Chartroom if available
2. Compose image generation prompt with platform-appropriate dimensions
3. Generate via image-gen tool
4. Post to Discord via Relay

## Output
Platform-sized graphic image ready for posting

Intent: Competent [I03]. Purpose: [P-TBD].
