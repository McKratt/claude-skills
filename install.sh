#!/usr/bin/env sh
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$REPO_DIR/skills"
TARGET_DIR="$HOME/.claude/skills"

mkdir -p "$TARGET_DIR"

warnings=0

for skill_md in "$SKILLS_DIR"/*/skill.md; do
  skill_dir="$(dirname "$skill_md")"
  skill_name="$(basename "$skill_dir")"
  target_link="$TARGET_DIR/$skill_name"

  if [ -L "$target_link" ] && [ "$(readlink "$target_link")" = "$skill_dir" ]; then
    echo "[skip]   $skill_name (already linked)"
  elif [ -e "$target_link" ]; then
    echo "[warn]   $skill_name — $target_link already exists (not managed by this script)"
    warnings=$((warnings + 1))
  else
    ln -s "$skill_dir" "$target_link"
    echo "[linked] $skill_name → $target_link"
  fi
done

[ "$warnings" -gt 0 ] && exit 1 || exit 0
