---
name: <kebab-case-name>
description: >
  <One sentence: what this skill does and when to use it.>
  Use when the user asks to <verb> <noun>. Triggers on "<phrase 1>", "<phrase 2>",
  "<phrase 3>". Do NOT use for <anti-trigger>.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

<!--
  BLACKSTRAW ENTERPRISE SKILL TEMPLATE
  ─────────────────────────────────────
  Copy this folder, rename it, fill every <placeholder>.
  Delete this comment block before committing.

  Frontmatter field guide
  ───────────────────────
  name          kebab-case, matches the folder name. Used as /slash-command.
  description   This is Claude's routing brain — it decides WHEN to auto-load
                the skill based on user intent. Write it like: "Use when the
                user does X. Triggers on Y, Z." Be specific — vague descriptions
                cause the skill to fire on wrong intents or never fire at all.
  allowed-tools Optional. Locks which Claude tools can run during this skill.
                Omit to allow all tools. Useful for read-only or restricted skills.

  File structure guide
  ────────────────────
  SKILL.md            Required. Main workflow. Keep under ~300 lines.
                      For anything longer, move detail into references/.
  references/         Optional. Supplementary markdown files Claude reads on
                      demand (e.g. "read references/api.md for full spec").
                      Keeps main SKILL.md tight and fast to load.

  Design rules
  ────────────
  1. Start with WHEN TO USE / NOT USE — saves Claude from misapplying the skill.
  2. Put hard constraints in a ## Hard Rules block — Claude treats these as invariants.
  3. Use step-by-step ## Workflow sections for repeatable processes.
  4. Reference other skills by name when chaining: "Load the python-dev skill first."
  5. Include concrete examples (good vs bad) — they outperform abstract instructions.
-->

# <Skill Display Name>

## Purpose

<One paragraph. What problem does this skill solve? What is the expected outcome
when it completes? Keep it to 3–4 sentences.>

## When to Use

**Use this skill when:**
- <Situation 1>
- <Situation 2>

**Do NOT use this skill when:**
- <Anti-situation 1 — prevents misapplication>
- <Anti-situation 2>

## Prerequisites

Before starting, confirm:
- [ ] <Prerequisite 1 — e.g. "The user has a Python project open">
- [ ] <Prerequisite 2 — e.g. "Dependencies installed (`uv sync`)">

---

## Workflow

### Step 1: <Step name>

<Instructions for step 1. Be specific. Tell Claude exactly what to do, not just
what to aim for.>

```bash
# Example command if applicable
```

**Checkpoint:** <What must be true before moving to Step 2?>

---

### Step 2: <Step name>

<Instructions for step 2.>

**Good pattern:**
```python
# example of correct approach
```

**Anti-pattern (avoid):**
```python
# example of wrong approach and why
```

---

### Step 3: <Step name>

<Instructions for step 3.>

---

## Hard Rules

- **ALWAYS** <do X> — reason: <why this is non-negotiable>
- **NEVER** <do Y> — reason: <why this would cause harm or wrong output>
- **PREFER** <A over B> when <condition>

---

## References

Detailed guides in `references/` (load as needed — do not load all upfront):

- **<topic>.md** — <one-line description of what it covers>
- **<examples>.md** — <one-line description>
