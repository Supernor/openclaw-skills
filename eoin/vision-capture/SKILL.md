---
name: vision-capture
description: PTV interview — multi-turn conversation where Eoin interviews Corinne about family goals and outputs Purpose Toward Vision codes. Sends to Robert for async validation via bearings.
version: 1.0.0
author: eoin
tags: [vision, ptv, purpose, goals, interview, north-star, direction, family, priorities]
---

# vision-capture — Purpose Toward Vision Interview

## Purpose

This is where the system learns WHY it exists — not from config, from Corinne's words. She defines (with Robert) the family's Purpose Toward Vision (PTV) codes. Every task the fleet does gets tagged to a purpose.

## When to Trigger

- After basic onboarding is complete (personality, name, initial goals captured)
- Corinne says "what should we be working on?" or "let's set some goals"
- Robert asks Eoin to capture Corinne's vision
- Bearings monthly_vision_check indicates stale or missing codes

## Prerequisites

- `onboard` skill completed (at least Steps 1-4)
- Corinne is comfortable enough with Eoin to have a deeper conversation
- If not ready yet: "We can do this anytime — whenever you're ready to think about the big picture."

## The Interview Flow

### Step 1: Open with Purpose (not with system language)

**Template:**
> I want to make sure I'm working on what actually matters to your family — not just busy work. What are the biggest things on your plate right now?

**Buttons:**
- `[Getting finances organized]`
- `[Growing the business]`
- `[Marketing & finding clients]`
- `[Managing our schedule]`
- `[Something else]`

She can pick multiple. Voice message welcome.

### Step 2: Drill Deeper (for each goal she picks)

**Template:**
> You picked "[her choice]." What would success look like for you?

She describes in her words (text or voice).

**Reflect back:**
> So success means [her exact words, cleaned up slightly]. Should I make this an official family goal I track?

**Buttons:** `[Yes, exactly]` `[Close, but...]` `[Let me explain more]`

### Step 3: Name the Goal (in her words)

If she confirms, ask for a short name:

> What should we call this goal? Something quick — like "get the money right" or "fill the pipeline."

Store her exact words. Don't translate to system language.

### Step 4: Repeat for Each Goal

Go through Steps 2-3 for every goal she mentioned. Aim for 3-5 goals — don't overwhelm.

If she has more than 5:
> That's a lot of ground to cover — which 3-5 feel most urgent right now? We can always add more later.

### Step 5: Validate with Robert (async)

After capturing all goals, send them to Robert for validation via bearings:

**Bearings question:**
```
Tool: bearings_ask
Params:
  question: "Corinne defined these family goals during her vision interview:
    1. [Goal name] — '[her words for success]'
    2. [Goal name] — '[her words for success]'
    3. [Goal name] — '[her words for success]'
    Anything to add, adjust, or remove?"
  options: ["Looks good", "I have changes", "Let's discuss"]
  target: "robert"
```

Tell Corinne:
> I've shared these with Robert so you're both on the same page. He can add or adjust — this is a family thing, not just yours.

### Step 6: Finalize PTV Codes

Once Robert validates:
- Assign PTV codes: P01, P02, P03... (internal, not shown to Corinne)
- Store in `workspace/PTV.md` (shared reference)
- Chart each code: `ptv-P##-[name]`
- Update Eoin's SOUL.md Purpose line with relevant codes

Tell Corinne:
> All set — your goals are locked in. Everything I do from now on ties back to what matters to you. You can add new goals or retire old ones anytime — just tell me.

## Output Format

For each goal captured:
```
Code: P##
Name: [her short name]
Success: [her words for what success looks like]
Domain: [Corinne / Robert / Joint]
Related Intents: [I## mapped by system, not shown to her]
```

## Ongoing Maintenance

- New purposes anytime: "Hey Eoin, we have a new goal..."
- Retire completed purposes: "We're good on that one"
- Monthly check-in via bearings asks both owners if any goals are stale
- Every task gets tagged to a purpose — she can ask "what are we doing toward [goal name]?"

## Rules

- Use HER language for goal names, not system jargon
- PTV codes (P##) are internal — she sees goal names
- Both owners validate — neither alone defines the direction
- Don't push for more than 5 goals in one sitting
- Voice messages are first-class input — encourage them
- If a goal doesn't pass the values test (P05 Doing Good gate), discuss it gently

## Anti-Patterns

- Don't say "PTV code" or "intent" to Corinne
- Don't pre-fill goals from Robert's list — let her define independently
- Don't skip validation with Robert — both owners shape the direction
- Don't make this feel like a corporate planning session — it's a family conversation
