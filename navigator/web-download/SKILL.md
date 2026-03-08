---
name: web-download
description: Download files from URLs to on-site storage
tags: [browser, web, download, file, media]
version: 1.0.0
---

# Web Download

Download files from the web and store them on-site.

## When to use
- "Download this file"
- "Save this PDF"
- "Get that image from Discord"
- "Grab the export from Google Drive"

## How to use

### Direct download (if URL is a direct file link)
Use web_fetch tool for direct downloads, browser for pages that require interaction.

### Browser-based download (requires clicking)
1. Navigate to the page
2. Click the download link/button
3. File saves to default download directory

### Storage locations
- Screenshots: /home/node/.openclaw/media/screenshots/
- Downloads: /home/node/.openclaw/media/downloads/
- Documents: workspace memory/ dir for agent-specific files

## Status Reporting
- On start: "Downloading [filename] from [source]"
- On complete: File path + size
- On failure: What broke, was it a permissions issue, expired link, etc.

## After Download
Report the on-site file path back to the requesting agent. If the file is an image or PDF that should be indexed in the Chartroom, note this in the result so the intake pipeline can process it.

Intent: Resourceful [I07]. Purpose: [P-TBD].
