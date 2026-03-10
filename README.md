# claude-skills

A collection of Claude Code skills for Java development workflows.

Skills are Markdown guides that Claude Code loads automatically to apply consistent patterns — testing conventions,
frameworks to use, code style decisions — without having to repeat them in every conversation.

## Skills

| Skill                                          | Triggers when...                              |
|------------------------------------------------|-----------------------------------------------|
| [`java-testing`](skills/java-testing/skill.md) | Writing, reviewing, or fixing Java tests      |
| [`spring-boot`](skills/spring-boot/skill.md)   | Building or reviewing Spring Boot applications |

## Installation

Skills must be placed in `~/.claude/skills/` for Claude Code to load them.

### Recommended: install script (links all skills at once)

```bash
git clone git@github.com:McKratt/claude-skills.git ~/git/claude-skills
cd ~/git/claude-skills
./install.sh
```

The script auto-discovers every skill under `skills/*/skill.md` and creates a symlink for each in `~/.claude/skills/`. Output per skill: `[linked]`, `[skip]` (already correct), or `[warn]` (conflict).

### Keeping skills up to date

```bash
cd ~/git/claude-skills && git pull
```

No re-run needed — the symlinks stay live and always point to the latest version. When new skills are added to the repo, run `./install.sh` once to link them.

### Manual single-skill install (selective)

```bash
ln -s ~/git/claude-skills/skills/<skill-name> ~/.claude/skills/<skill-name>
```

## Adding a new skill

1. Create a directory under `skills/<skill-name>/`
2. Add a `skill.md` with the required frontmatter:

```markdown
---
name: skill-name
description: Use when <specific trigger condition>
---
```

3. Run `./install.sh` to link the new skill (or manually: `ln -s ~/git/claude-skills/skills/<skill-name> ~/.claude/skills/<skill-name>`)

The `description` field controls when Claude invokes the skill automatically — write it as a concrete trigger condition,
not a vague summary.
