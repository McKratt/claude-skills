# claude-skills

A collection of Claude Code skills for Java development workflows.

Skills are Markdown guides that Claude Code loads automatically to apply consistent patterns — testing conventions,
frameworks to use, code style decisions — without having to repeat them in every conversation.

## Skills

| Skill                                          | Triggers when...                         |
|------------------------------------------------|------------------------------------------|
| [`java-testing`](skills/java-testing/skill.md) | Writing, reviewing, or fixing Java tests |

## Installation

Skills must be placed in `~/.claude/skills/` for Claude Code to load them.

### Recommended: symlink (stays in sync with the repo)

```bash
git clone git@github.com:McKratt/claude-skills.git ~/git/claude-skills

mkdir -p ~/.claude/skills

# Link each skill — repeat for new skills added later
ln -s ~/git/claude-skills/skills/java-testing ~/.claude/skills/java-testing
```

### Alternative: copy (one-time snapshot)

```bash
cp -r ~/git/claude-skills/skills/java-testing ~/.claude/skills/java-testing
```

### Keeping skills up to date (symlink approach)

```bash
cd ~/git/claude-skills && git pull
```

No further action needed — the symlinks always point to the latest version.

## Adding a new skill

1. Create a directory under `skills/<skill-name>/`
2. Add a `skill.md` with the required frontmatter:

```markdown
---
name: skill-name
description: Use when <specific trigger condition>
---
```

3. Symlink the new directory into `~/.claude/skills/`

The `description` field controls when Claude invokes the skill automatically — write it as a concrete trigger condition,
not a vague summary.
