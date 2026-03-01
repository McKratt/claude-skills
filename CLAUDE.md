# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repository is for developing and storing custom Claude Code skills — reusable process guides that teach Claude instances specific techniques, patterns, or workflows.

## Skill Architecture

Skills are Markdown files with YAML frontmatter and live in:
- `~/.claude/skills/` — personal skills loaded automatically by Claude Code
- Plugin packages (e.g., `superpowers@claude-plugins-official`) — community skills installed via `/plugin install`

A skill file follows this structure:

```markdown
---
name: skill-name
description: Use when [trigger condition] — this is what Claude uses to match the skill
---

# Skill Title

## Overview
...

## Steps / Guidance
...
```

The `description` frontmatter is critical: it determines when Claude automatically invokes the skill.

## Skill Development Workflow

Skills follow a TDD-like cycle:

1. **RED** — Run a baseline subagent scenario to confirm undesired behavior occurs *without* the skill
2. **GREEN** — Write the skill document addressing the specific violations observed
3. **REFACTOR** — Identify rationalizations the agent still uses to bypass the skill; plug loopholes

**Do not write a skill until you have watched an agent fail without it.** If you haven't observed the failure mode, you don't know what to teach.

## What Belongs Here vs. CLAUDE.md

- **Skills** — reusable techniques applicable across projects (goes in `~/.claude/skills/` or this repo)
- **Project conventions** — project-specific constraints (goes in the project's `CLAUDE.md`)
- **Automatable rules** — if enforceable with linting or validation, automate it instead

## Installed Global Plugins (reference)

Active plugins providing skills: `superpowers`, `commit-commands`, `code-simplifier`, `claude-code-setup`, `github`, `security-guidance`. See `~/.claude/settings.json` for the full list.
