---
name: palette-extract
description: Extract color palette from a color.adobe.com URL or image. Outputs hex values, CSS custom properties, and color role assignments.
version: 1.0.0
author: designer
tags:
  - palette
  - color
  - extract
  - adobe
  - css
  - brand
  - theme
  - design
  - visual
trigger:
  command: /palette
  keywords:
    - extract palette
    - color palette
    - get colors
    - adobe color
    - color scheme
---

# palette-extract

Pull colors from a source and assign roles.

## Inputs
- color.adobe.com URL
- OR list of hex values
- OR image to sample from

## Procedure
1. Parse source for color values
2. Assign roles: primary, secondary, accent, background, text
3. Generate CSS custom properties
4. Generate a color swatch visual (SVG)
5. Store in Chartroom: `palette-<project-name>`

## Output
- Hex values with role assignments
- CSS `:root` block
- Visual swatch

Intent: Resourceful [I07]. Purpose: [P-TBD].
