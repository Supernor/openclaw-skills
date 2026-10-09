---
name: mockup
description: Generate website mockups and web design previews from palette, content, and goals. Handles site design, page design, and landing page layouts. Two modes — AI-generated concept image (fast) or HTML/CSS preview with Navigator screenshot (accurate).
version: 1.0.0
author: designer
tags:
  - mockup
  - website
  - preview
  - design
  - visual
  - layout
  - prototype
  - comp
  - web design
  - site design
  - page design
  - landing page
trigger:
  command: /mockup
  keywords:
    - website mockup
    - page preview
    - site design
    - website concept
    - mock up
    - website layout
---

# mockup

Generate a website mockup from palette + content + goals.

## Inputs
- **Palette**: color.adobe.com URL, hex values, or "extract from [URL]"
- **Content**: text, images, or brief describing what goes on the page
- **Goals**: what the site should accomplish (sell, inform, portfolio, etc.)

## Mode 1: AI Concept (Fast)
1. Compose a detailed image generation prompt from inputs
2. Generate via `openai-image-gen` or `nano-banana-pro`
3. Post image to Discord via Relay

## Mode 2: HTML/CSS Preview (Accurate)
1. Generate complete HTML/CSS with real layout, colors, and content
2. Save to `/tmp/openclaw-design/mockup-<id>.html`
3. Request Navigator to open and screenshot
4. Post screenshot to Discord via Relay

## Output
Visual mockup + palette summary + revision notes

Intent: Competent [I03]. Purpose: [P-TBD].
