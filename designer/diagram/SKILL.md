---
name: diagram
description: Create flowcharts, architecture diagrams, sequence diagrams, state diagrams, and other visual diagrams using Mermaid. Renders to PNG or SVG.
version: 1.0.0
author: designer
tags:
  - diagram
  - flowchart
  - architecture
  - sequence
  - mermaid
  - visualization
  - chart
  - graph
  - flow
  - visual
  - design
  - architecture diagram
trigger:
  command: /diagram
  keywords:
    - create diagram
    - flowchart
    - architecture diagram
    - sequence diagram
    - draw flow
    - visualize workflow
    - state diagram
---

# diagram

Create visual diagrams from descriptions using Mermaid.

## Supported Types
- `flowchart` — processes, decision trees, workflows
- `sequenceDiagram` — agent interactions, API flows, message passing
- `classDiagram` — data models, relationships
- `stateDiagram-v2` — state machines
- `erDiagram` — database schemas
- `gantt` — project timelines
- `mindmap` — brainstorming, idea mapping
- `pie` — proportions

## Procedure
1. Understand what needs to be visualized
2. Choose the right diagram type
3. Write Mermaid syntax
4. Render: `echo '<code>' | mmdc -i /dev/stdin -o /tmp/openclaw-design/diagram.png -t dark -b transparent`
5. Post to Discord via Relay

## Output
Rendered diagram image + Mermaid source code for future editing
