---
name: vision-refresh
description: PTV code review and refresh for Robert. Quick check on whether north stars are current, stale, or missing. Robert's equivalent of Eoin's vision-capture skill.
version: 1.0.0
author: relay
tags: [vision, ptv, purpose, refresh, review, north-star, direction, goals]
---

# vision-refresh — PTV Code Review

## Purpose

Robert doesn't start from scratch — he refines. This skill shows current PTV codes and asks "any stale? any new?" Quick review, not a full interview.

## When to Trigger

- Robert says "vision refresh", "PTV check", "north stars", "priorities"
- Monthly via bearings `monthly_vision_check` prompt
- After a significant project milestone or family change

## The Flow

### Step 1: Show Current State

> **PTV Codes — current:**
> - **P01** Family Financial Health — "know where every dollar goes"
> - **P02** Marketing Pipeline — "leads coming in without chasing"
> - **P03** Client Delivery — "website in hand while they're still excited"
> - **P04** System Visibility — "dashboard — I need to see what's happening"
> - **P05** Doing Good — "do a lot of good in the world"
>
> Any stale? Any new?

**Buttons:** `[All current]` `[One needs updating]` `[New priority]` `[Retire one]`

### Step 2: Handle Changes

**Update:** "Which code? What changed?" → Update PTV.md, chart the change.
**New:** "What's the goal? One line." → Assign next P## code, add to PTV.md, chart it.
**Retire:** "Which one?" → Mark as retired in PTV.md, chart the retirement.

### Step 3: Cross-Validate

If changes affect Corinne's domain codes (P01, P02):
> This touches Corinne's domain. Queue bearings for her validation?

**Buttons:** `[Yes, check with her]` `[No, I've discussed it]`

### Step 4: Propagate

- Update `workspace/PTV.md`
- Chart changes as `ptv-update-[code]-[date]`
- Update affected agent SOUL.md Purpose lines if mapping changes
- Notify Captain for fleet-wide awareness

## Rules

- Keep it fast — Robert doesn't want an interview, he wants a review
- Show the current state first so he can react, not recall
- Chart every change — PTV code changes are governance-level
- Always cross-validate with Corinne on codes that touch her domain
- Use buttons — Robert prefers clicking to typing
